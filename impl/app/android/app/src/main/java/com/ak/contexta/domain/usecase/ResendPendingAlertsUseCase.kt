package com.ak.contexta.domain.usecase

import android.util.Log
import com.ak.contexta.domain.AppInfoProvider
import com.ak.contexta.domain.DeveloperAlertSender
import com.ak.contexta.domain.ErrorContext
import com.ak.contexta.domain.error.AppError
import com.ak.contexta.domain.error.LlmFatalCode
import com.ak.contexta.domain.error.StructuralCode
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 补发未送达的飞书告警。
 *
 * 实时告警是尽力而为：生成期间进程可能被系统终止（后台冻结/Job 超时），
 * `sendArticleFailure` / `sendBatchReady` 的 HTTP 调用可能未完成就随进程消失。
 * 错误事件已落库（generation_error_log），批次状态已落库（article_batch），
 * 但通知标记（notified_at / ready_notified_at）仍为 null —— 启动时补发这些告警。
 *
 * 幂等保证：
 * - 告警发送成功才回写 notified_at（SQL 带 `AND notified_at IS NULL` 条件，只写一次）
 * - 发送失败（返回 false）不回写，下次启动继续补发
 */
@Singleton
class ResendPendingAlertsUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val alertSender: DeveloperAlertSender,
    private val timeProvider: TimeProvider,
    private val appInfo: AppInfoProvider
) {
    companion object {
        private const val TAG = "ResendPendingAlerts"
        /** 只补发最近 24 小时内的错误，更早的视为已处理完毕（人工可见于错误历史）。 */
        private const val LOOKBACK_MS = 24 * 60 * 60 * 1000L
    }

    suspend operator fun invoke() {
        val now = timeProvider.nowMillis()
        val sinceIso = Instant.ofEpochMilli(now - LOOKBACK_MS)
            .atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)

        var resent = 0
        // 1. 补发未通知的错误告警
        val unnotifiedErrors = articleRepository.getUnnotifiedErrors(sinceIso)
        for (error in unnotifiedErrors) {
            val context = ErrorContext(
                batchId = if (error.entityType == "BATCH") error.entityId
                else articleRepository.getArticle(error.entityId)?.batchId,
                articleId = if (error.entityType == "ARTICLE") error.entityId else null,
                appVersion = appInfo.versionCode,
                timestamp = now
            )
            val sent = when (error.errorCode) {
                "LLM_FATAL" -> alertSender.sendLlmFatalError(
                    AppError.LlmFatal(LlmFatalCode.AUTH_FAILED, error.errorMessage, null),
                    context
                )
                "STRUCTURAL_PIPELINE_BLOCKED", "PIPELINE_BLOCKING" -> alertSender.sendStructuralError(
                    AppError.Structural(StructuralCode.UNEXPECTED_ERROR, error.errorMessage, null),
                    context
                )
                else -> alertSender.sendArticleFailure(
                    status = if (error.errorCode == "LLM_RECOVERABLE_EXHAUSTED") "FAILED" else "TIMEOUT",
                    errorCode = error.errorCode,
                    errorMessage = error.errorMessage,
                    context = context
                )
            }
            if (sent) {
                articleRepository.markErrorNotified(error.id)
                resent++
            }
        }

        // 2. 补发未通知的批次完成告警
        val unnotifiedBatches = articleRepository.getReadyBatchesUnnotified()
        for (batch in unnotifiedBatches) {
            val articleCount = articleRepository.getArticles(batch.id).size
            val sent = alertSender.sendBatchReady(
                batchId = batch.id,
                articleCount = articleCount,
                batchGeneratedOn = batch.generatedOn,
                batchDifficulty = batch.difficultyLevelSnapshot,
                context = ErrorContext(batch.id, null, appInfo.versionCode, now)
            )
            if (sent) {
                articleRepository.markBatchReadyNotified(batch.id)
                resent++
            }
        }

        if (resent > 0) {
            Log.i(TAG, "Resent $resent pending alert(s): ${unnotifiedErrors.size} error(s), ${unnotifiedBatches.size} batch(es)")
        }
    }
}
