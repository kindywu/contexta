package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.AppInfoProvider
import com.ak.contexta.domain.DeveloperAlertSender
import com.ak.contexta.domain.ErrorContext
import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.error.LlmFatalException
import com.ak.contexta.domain.error.LlmRecoverableExhaustedException
import com.ak.contexta.domain.error.LlmTimeoutException
import com.ak.contexta.domain.error.PipelineBlockingException
import com.ak.contexta.domain.generation.buildArticleSystemPrompt
import com.ak.contexta.domain.generation.buildArticleUserPrompt
import com.ak.contexta.domain.generation.categoryToDifficulty
import com.ak.contexta.domain.generation.parseArticleLlmResponse
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 通过 LLM 生成一个批次的所有文章。
 * 从 [ArticleGenerationWorker.processBatch] 提取。
 */
@Singleton
class GenerateArticlesUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val llmClient: LlmClient,
    private val timeProvider: TimeProvider,
    private val appInfo: AppInfoProvider,
    private val alertSender: DeveloperAlertSender
) {
    /**
     * 为指定的批次生成所有文章。
     */
    suspend operator fun invoke(batchId: Long, appVersionCode: Int?) {
        val articles = articleRepository.getArticles(batchId)
        if (articles.isEmpty()) {
            articleRepository.markBatchReady(batchId)
            return
        }

        for (article in articles) {
            if (article.status.name == "SUCCESS") continue

            if (!articleRepository.claimArticle(article.id)) continue

            try {
                val difficulty = categoryToDifficulty(article.contentCategory)
                val result = llmClient.call(
                    buildArticleSystemPrompt(difficulty),
                    buildArticleUserPrompt(article.contentCategory, article.orderIndex)
                )

                val (title, paragraphs) = parseArticleLlmResponse(result.content)
                articleRepository.completeArticle(
                    articleId = article.id,
                    title = title,
                    paragraphs = paragraphs,
                    retryCount = result.retryCount
                )

            } catch (e: LlmFatalException) {
                val errorLogId = articleRepository.fatalArticle(article.id, "LLM_FATAL", e.message, article.retryCount)
                val sent = alertSender.sendLlmFatalError(
                    com.ak.contexta.domain.error.AppError.LlmFatal(
                        code = com.ak.contexta.domain.error.LlmFatalCode.AUTH_FAILED,
                        message = e.message ?: "Unknown",
                        cause = e
                    ),
                    ErrorContext(batchId, article.id, appVersionCode ?: 0, timeProvider.nowMillis())
                )
                // 告警送达才回写 notified_at；进程被杀导致通知丢失时，启动补发会重发
                if (sent) errorLogId?.let { articleRepository.markErrorNotified(it) }
                continue

            } catch (e: LlmRecoverableExhaustedException) {
                val errorLogId = articleRepository.failArticle(
                    article.id, "FAILED", "LLM_RECOVERABLE_EXHAUSTED", e.message,
                    retryCount = article.retryCount
                )
                val sent = alertSender.sendArticleFailure(
                    status = "FAILED",
                    errorCode = "LLM_RECOVERABLE_EXHAUSTED",
                    errorMessage = e.message ?: "Unknown",
                    context = ErrorContext(batchId, article.id, appVersionCode ?: 0, timeProvider.nowMillis())
                )
                if (sent) errorLogId?.let { articleRepository.markErrorNotified(it) }
                continue

            } catch (e: PipelineBlockingException) {
                val articleErrorLogId = articleRepository.fatalArticle(article.id, "PIPELINE_BLOCKING", e.message, article.retryCount)
                val batchErrorLogId = articleRepository.markBatchBlocked(batchId, e.message ?: "Unknown", appVersionCode ?: 0)
                val sent = alertSender.sendStructuralError(
                    com.ak.contexta.domain.error.AppError.Structural(
                        code = com.ak.contexta.domain.error.StructuralCode.UNEXPECTED_ERROR,
                        message = e.message ?: "Unknown",
                        cause = e
                    ),
                    ErrorContext(batchId, article.id, appVersionCode ?: 0, timeProvider.nowMillis())
                )
                if (sent) {
                    articleErrorLogId?.let { articleRepository.markErrorNotified(it) }
                    batchErrorLogId?.let { articleRepository.markErrorNotified(it) }
                }
                throw e

            } catch (e: LlmTimeoutException) {
                // 协程级超时：预期内的失败（网络挂起/后台节流），
                // 单独分类为 LLM_TIMEOUT，区别于真正的 UNEXPECTED 代码级错误
                val errorLogId = articleRepository.failArticle(
                    article.id, "TIMEOUT", "LLM_TIMEOUT", e.message,
                    retryCount = article.retryCount
                )
                val sent = alertSender.sendArticleFailure(
                    status = "TIMEOUT",
                    errorCode = "LLM_TIMEOUT",
                    errorMessage = e.message ?: "Unknown",
                    context = ErrorContext(batchId, article.id, appVersionCode ?: 0, timeProvider.nowMillis())
                )
                if (sent) errorLogId?.let { articleRepository.markErrorNotified(it) }
                continue

            } catch (e: Exception) {
                val errorLogId = articleRepository.failArticle(
                    article.id, "TIMEOUT", "UNEXPECTED", e.message,
                    retryCount = article.retryCount
                )
                val sent = alertSender.sendArticleFailure(
                    status = "TIMEOUT",
                    errorCode = "UNEXPECTED",
                    errorMessage = e.message ?: "Unknown",
                    context = ErrorContext(batchId, article.id, appVersionCode ?: 0, timeProvider.nowMillis())
                )
                if (sent) errorLogId?.let { articleRepository.markErrorNotified(it) }
                continue
            }
        }

        when {
            articleRepository.hasFatalArticle(batchId) -> { /* leave as GENERATING */ }
            articleRepository.isBatchComplete(batchId) -> {
                articleRepository.markBatchReady(batchId)
                // 取批次信息（生成日期/难度），随完成通知一起展示
                val batch = articleRepository.getBatchById(batchId)
                val sent = alertSender.sendBatchReady(
                    batchId = batchId,
                    articleCount = articles.size,
                    batchGeneratedOn = batch?.generatedOn,
                    batchDifficulty = batch?.difficultyLevelSnapshot,
                    context = ErrorContext(batchId, null, appVersionCode ?: 0, timeProvider.nowMillis())
                )
                // 通知送达才回写 ready_notified_at；进程被杀导致通知丢失时，启动补发会重发
                if (sent) articleRepository.markBatchReadyNotified(batchId)
            }
        }
    }
}
