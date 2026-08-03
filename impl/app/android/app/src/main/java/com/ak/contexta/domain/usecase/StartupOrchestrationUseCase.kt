package com.ak.contexta.domain.usecase

import android.util.Log
import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.time.TimeProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 应用启动时的编排逻辑：reconciliation、pipeline 解除阻塞、每日批次分配。
 *
 * **流程：**
 * 1. 检查 pipeline 是否阻塞 → 尝试恢复或返回阻塞状态
 * 2. 检查是否完成 onboarding → 返回 NeedsOnboarding
 * 3. 修复孤儿文章（重置 GENERATING/TIMEOUT/FAILED → PENDING）
 * 4. 重新调度所有卡在 GENERATING 状态的 batch 的 Worker
 * 5. 检查今天是否已有 daily_learning 分配 → Ready
 * 6. 查找 max(ref_batch_date) 之后的 READY 批次（严格晚于已消费日期，不回头分配 seed 旧批次）
 *    - 找到 → 分配给今天，触发下一批前置生成 → Ready
 *    - 未找到 → NeedsInitialBatch（调用方创建并触发生成）
 */
@Singleton
class StartupOrchestrationUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val timeProvider: TimeProvider,
    private val triggerNextBatch: TriggerNextBatchUseCase,
    private val generationScheduler: BackgroundWorkScheduler,
    private val resendPendingAlerts: ResendPendingAlertsUseCase
) {
    sealed class StartupResult {
        data object PipelineBlocked : StartupResult()
        data object NeedsOnboarding : StartupResult()
        data object Ready : StartupResult()
        data class NeedsInitialBatch(val difficulty: String, val dailyCount: Int) : StartupResult()
    }

    /**
     * Full startup routine: called once when the app opens.
     */
    suspend operator fun invoke(currentVersionCode: Int): StartupResult {
        // 1. Check pipeline block
        if (articleRepository.isPipelineBlocked()) {
            val recovered = articleRepository.recoverIfNewerVersion(currentVersionCode)
            if (!recovered) return StartupResult.PipelineBlocked
        }

        // 2. Check onboarding
        val settings = settingsRepository.getSettings()
        if (settings == null || !settings.isOnboarded) return StartupResult.NeedsOnboarding

        // 3. 先查询卡在 GENERATING 的 batch（reconciliation 会重置它们）
        val stuckBatches = articleRepository.getGeneratingBatches()

        // 4. Reconcile orphan GENERATING/TIMEOUT/FAILED articles + reset GENERATING batches
        articleRepository.reconcileOrphanArticles()

        // 5. 重新调度之前卡死的 batch
        //    reconcileOrphanArticles 已将孤儿文章和 batch 重置为 PENDING，
        //    这里重新 enqueue Worker 让它们重新被认领生成。
        if (stuckBatches.isNotEmpty()) {
            Log.i("StartupOrch", "Re-scheduling ${stuckBatches.size} stuck batch(es)")
            stuckBatches.forEach { batch ->
                generationScheduler.scheduleBatchGeneration(batch.id)
            }
        }

        // 5.5 补发未送达的飞书告警（生成期间进程被终止时，实时告警可能丢失）
        //     失败不影响启动主流程——下次启动还会再试
        runCatching { resendPendingAlerts() }
            .onFailure { Log.w("StartupOrch", "Resend pending alerts failed", it) }

        val today = timeProvider.todayDateString()

        // 4. Check if today already has a daily_learning assignment
        val todayBatch = articleRepository.getAssignedBatchForDate(today)
        if (todayBatch != null) {
            // 即使今天已有分配，仍需确保未来有预生成的批次可用。
            // 如果 daily_learning 引用的最后日期之后没有 READY 批次，则触发生成。
            triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
            return StartupResult.Ready
        }

        // 5. Find next READY batch for the user's difficulty.
        //    只找已消费批次日期之后的批次（严格 >）：批次按时间顺序消费，不回头分配 seed 旧批次。
        //    seed 历史批次（generated_on=03-29）在首次使用被消费后不再分配；
        //    否则 TriggerNextBatchUseCase 会因"已有未来批次"跳过新批次生成。
        val maxRefDate = articleRepository.getMaxRefBatchDate()
        val nextBatch = articleRepository.findNextReadyBatch(
            difficulty = settings.difficultyLevel,
            afterDate = maxRefDate
        )

        if (nextBatch != null && nextBatch.status == BatchStatus.READY) {
            articleRepository.assignBatchForToday(
                batchId = nextBatch.id,
                refBatchDate = nextBatch.generatedOn ?: today,
                dailyCount = settings.dailyArticleCount
            )
            // 触发下一批的前置生成
            triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
            return StartupResult.Ready
        }

        // 6. No READY batch available - need to create and generate one
        return StartupResult.NeedsInitialBatch(
            difficulty = settings.difficultyLevel,
            dailyCount = settings.dailyArticleCount
        )
    }
}
