package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.time.TimeProvider
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 应用启动时的编排逻辑：reconciliation、pipeline 解除阻塞、批次推进。
 * 从 [GenerationManager.onAppStart] 提取。
 */
@Singleton
class StartupOrchestrationUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val triggerNextBatch: TriggerNextBatchUseCase,
    private val timeProvider: TimeProvider
) {
    sealed class StartupResult {
        data object PipelineBlocked : StartupResult()
        data object NeedsOnboarding : StartupResult()
        data object Ready : StartupResult()
        data class NeedsInitialBatch(val difficulty: String, val dailyCount: Int) : StartupResult()
        data class WaitingForGeneration(val batchId: Long) : StartupResult()
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

        // 3. Reconcile orphan GENERATING articles
        articleRepository.reconcileOrphanArticles()

        // 4. Check and promote batch if needed
        val currentBatch = articleRepository.getCurrentBatch()
        val nextBatch = articleRepository.getNextBatch()
        val today = timeProvider.todayDateString()

        if (currentBatch == null && nextBatch == null) {
            return StartupResult.NeedsInitialBatch(
                difficulty = settings.difficultyLevel,
                dailyCount = settings.dailyArticleCount
            )
        }

        if (currentBatch == null && nextBatch != null) {
            if (nextBatch.status == BatchStatus.READY || nextBatch.status == BatchStatus.GENERATING) {
                if (nextBatch.difficultyLevelSnapshot == settings.difficultyLevel) {
                    articleRepository.promoteNextToCurrent(nextBatch.id)
                    triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
                    return StartupResult.Ready
                } else {
                    triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
                    return StartupResult.Ready
                }
            }
        }

        if (currentBatch != null && nextBatch != null) {
            val unlockedOn = currentBatch.unlockedOn ?: ""
            if (isNextDay(unlockedOn, today) && nextBatch.status == BatchStatus.READY) {
                if (nextBatch.difficultyLevelSnapshot == settings.difficultyLevel) {
                    articleRepository.promoteNextToCurrent(nextBatch.id)
                    triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
                    return StartupResult.Ready
                } else {
                    triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
                    return StartupResult.Ready
                }
            }

            if (isNextDay(unlockedOn, today) &&
                (nextBatch.status == BatchStatus.GENERATING || nextBatch.status == BatchStatus.PENDING)) {
                return StartupResult.WaitingForGeneration(nextBatch.id)
            }
        }

        // Ensure NEXT batch exists if missing or expired
        if (nextBatch == null || nextBatch.status == BatchStatus.EXPIRED) {
            triggerNextBatch(settings.difficultyLevel, settings.dailyArticleCount)
        }

        return StartupResult.Ready
    }

    private fun isNextDay(unlockedOn: String, today: String): Boolean {
        if (unlockedOn.isBlank()) return false
        val zoneId = ZoneId.of("Asia/Shanghai")
        val unlocked = LocalDate.parse(unlockedOn)
        val todayDate = LocalDate.parse(today)
        return todayDate > unlocked
    }
}
