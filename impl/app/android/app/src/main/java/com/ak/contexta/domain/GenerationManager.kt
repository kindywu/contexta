package com.ak.contexta.domain

import android.util.Log
import com.ak.contexta.data.local.ContextaTypeConverters
import com.ak.contexta.data.local.dao.GenerationPipelineStatusDao
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.BatchType
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.worker.GenerationScheduler
import kotlinx.coroutines.flow.first
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Orchestrates the batch generation lifecycle:
 * - App startup: reconciliation, pipeline unblocking
 * - Batch promotion (NEXT → CURRENT when a new day arrives)
 * - Triggering background generation for new batches
 */
@Singleton
class GenerationManager @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val pipelineStatusDao: GenerationPipelineStatusDao,
    private val generationScheduler: GenerationScheduler
) {
    companion object {
        private const val TAG = "GenerationManager"
        private val CONTENT_CATEGORIES = mapOf(
            "LOW" to listOf("DAILY_CONVERSATION", "SCENE_DESCRIPTION", "SIMPLE_STORY"),
            "MEDIUM" to listOf("NEWS", "EXPOSITORY", "ARGUMENTATIVE", "PERSONAL_ESSAY"),
            "HIGH" to listOf("ACADEMIC_EXCERPT", "DEBATE_SPEECH", "LEGAL_DOCUMENT", "ART_CRITICISM", "CLASSIC_NOVEL_EXCERPT")
        )
    }

    /**
     * Full startup routine: called once when the app opens.
     * Returns whether onboarding is needed.
     */
    suspend fun onAppStart(currentVersionCode: Int): StartupResult {
        Log.i(TAG, "onAppStart: currentVersionCode=$currentVersionCode")

        // 1. Check pipeline block
        if (articleRepository.isPipelineBlocked()) {
            Log.w(TAG, "Pipeline blocked, trying to recover")
            val recovered = articleRepository.recoverIfNewerVersion(currentVersionCode)
            if (!recovered) {
                return StartupResult.PipelineBlocked
            }
        }

        // 2. Check onboarding
        val settings = settingsRepository.getSettings()
        if (settings == null || !settings.isOnboarded) {
            return StartupResult.NeedsOnboarding
        }

        // 3. Reconcile orphan GENERATING articles
        articleRepository.reconcileOrphanArticles()

        // 4. Check and promote batch if needed
        val currentBatch = articleRepository.getCurrentBatch()
        val nextBatch = articleRepository.getNextBatch()

        Log.i(TAG, "currentBatch=${currentBatch?.id}/${currentBatch?.status}, nextBatch=${nextBatch?.id}/${nextBatch?.status}")

        val today = ContextaTypeConverters.currentDateString()

        if (currentBatch == null && nextBatch == null) {
            Log.i(TAG, "Fresh start: need initial batch")
            // Fresh start: create CURRENT batch
            return StartupResult.NeedsInitialBatch(
                difficulty = settings.difficultyLevel,
                dailyCount = settings.dailyArticleCount
            )
        }

        if (currentBatch == null && nextBatch != null) {
            Log.i(TAG, "No current batch, promoting next")
            // NEXT can be promoted directly (no CURRENT to compare against)
            if (nextBatch.status == BatchStatus.READY || nextBatch.status == BatchStatus.GENERATING) {
                articleRepository.promoteNextToCurrent(nextBatch.id)
                triggerNextBatchGeneration(settings.difficultyLevel, settings.dailyArticleCount)
                return StartupResult.Ready
            }
        }

        if (currentBatch != null && nextBatch != null) {
            val unlockedOn = currentBatch.unlockedOn ?: ""
            // Check if a natural day has passed since CURRENT was unlocked
            if (isNextDay(unlockedOn, today) && nextBatch.status == BatchStatus.READY) {
                Log.i(TAG, "Next day, promoting next to current")
                articleRepository.promoteNextToCurrent(nextBatch.id)
                triggerNextBatchGeneration(settings.difficultyLevel, settings.dailyArticleCount)
                return StartupResult.Ready
            }

            // If NEXT is still generating and a day has passed, show loading
            if (isNextDay(unlockedOn, today) &&
                (nextBatch.status == BatchStatus.GENERATING || nextBatch.status == BatchStatus.PENDING)) {
                Log.i(TAG, "Next day but next batch still generating")
                return StartupResult.WaitingForGeneration(nextBatch.id)
            }
        }

        // Ensure NEXT batch exists if missing, expired, or invalidated
        if (nextBatch == null ||
            nextBatch.status == BatchStatus.EXPIRED ||
            nextBatch.status == BatchStatus.INVALIDATED
        ) {
            Log.i(TAG, "Creating new NEXT batch (current: ${currentBatch?.status})")
            triggerNextBatchGeneration(settings.difficultyLevel, settings.dailyArticleCount)
        }

        return StartupResult.Ready
    }

    /**
     * Start generation for the first (initial) batch after onboarding.
     */
    suspend fun startInitialGeneration(difficulty: String, dailyCount: Int): Long {
        Log.i(TAG, "startInitialGeneration: difficulty=$difficulty, dailyCount=$dailyCount")
        val batchId = articleRepository.createBatch(
            batchType = BatchType.CURRENT.value,
            difficulty = difficulty,
            dailyCount = dailyCount
        )
        val categories = pickCategories(difficulty, dailyCount)
        articleRepository.createArticles(batchId, categories)
        // The caller (ViewModel) will trigger WorkManager
        return batchId
    }

    /**
     * Create and trigger generation for the NEXT batch in the background.
     */
    suspend fun triggerNextBatchGeneration(difficulty: String, dailyCount: Int) {
        val existingNext = articleRepository.getNextBatch()
        if (existingNext != null &&
            existingNext.status != BatchStatus.EXPIRED &&
            existingNext.status != BatchStatus.INVALIDATED
        ) {
            Log.i(TAG, "NEXT batch ${existingNext.id} exists and active (${existingNext.status}), skipping")
            return // already exists and still active
        }

        val batchId = articleRepository.createBatch(
            batchType = BatchType.NEXT.value,
            difficulty = difficulty,
            dailyCount = dailyCount
        )
        Log.i(TAG, "Created NEXT batch $batchId, scheduling Worker")
        val categories = pickCategories(difficulty, dailyCount)
        articleRepository.createArticles(batchId, categories)
        // Schedule WorkManager to generate the articles via LLM
        generationScheduler.scheduleBatchGeneration(batchId)
        Log.i(TAG, "Worker scheduled for batch $batchId")
    }

    private suspend fun pickCategories(difficulty: String, count: Int): List<String> {
        val available = CONTENT_CATEGORIES[difficulty] ?: CONTENT_CATEGORIES["MEDIUM"]!!
        // Round-robin starting from a random offset to add variety
        val offset = (System.currentTimeMillis() % 1000).toInt() % available.size
        return (0 until count).map { i ->
            available[(offset + i) % available.size]
        }
    }

    private fun isNextDay(unlockedOn: String, today: String): Boolean {
        if (unlockedOn.isBlank()) return false
        val zoneId = ZoneId.of("Asia/Shanghai")
        val unlocked = LocalDate.parse(unlockedOn)
        val todayDate = LocalDate.parse(today)
        return todayDate > unlocked
    }

    sealed class StartupResult {
        data object PipelineBlocked : StartupResult()
        data object NeedsOnboarding : StartupResult()
        data object Ready : StartupResult()
        data class NeedsInitialBatch(val difficulty: String, val dailyCount: Int) : StartupResult()
        data class WaitingForGeneration(val batchId: Long) : StartupResult()
    }
}
