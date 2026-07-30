package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.BatchType
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 创建并调度 NEXT 批次的后台生成任务。
 * 从 [GenerationManager.triggerNextBatchGeneration] 提取。
 */
@Singleton
class TriggerNextBatchUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val generationScheduler: BackgroundWorkScheduler,
    private val timeProvider: TimeProvider
) {
    companion object {
        const val MAX_ARTICLES_PER_BATCH = 5

        val CONTENT_CATEGORIES = mapOf(
            "LOW" to listOf("DAILY_CONVERSATION", "SCENE_DESCRIPTION", "SIMPLE_STORY"),
            "MEDIUM" to listOf("NEWS", "EXPOSITORY", "ARGUMENTATIVE", "PERSONAL_ESSAY"),
            "HIGH" to listOf("ACADEMIC_EXCERPT", "DEBATE_SPEECH", "LEGAL_DOCUMENT", "ART_CRITICISM", "CLASSIC_NOVEL_EXCERPT")
        )
    }

    /**
     * Create and trigger generation for the NEXT batch in the background.
     */
    suspend operator fun invoke(difficulty: String, dailyCount: Int) {
        val existingNext = articleRepository.getNextBatch()
        if (existingNext != null && existingNext.status != BatchStatus.EXPIRED) {
            if (existingNext.difficultyLevelSnapshot == difficulty) {
                return // Same difficulty, no need to recreate
            }
        }

        val batchId = articleRepository.createBatch(
            batchType = BatchType.NEXT.value,
            difficulty = difficulty,
            dailyCount = dailyCount
        )
        val categories = pickCategories(difficulty)
        articleRepository.createArticles(batchId, categories)
        generationScheduler.scheduleBatchGeneration(batchId)
    }

    /** Round-robin category selection from the difficulty group. */
    fun pickCategories(difficulty: String): List<String> {
        val available = CONTENT_CATEGORIES[difficulty] ?: CONTENT_CATEGORIES["MEDIUM"]!!
        val offset = (timeProvider.nowMillis() % 1000).toInt() % available.size
        return (0 until MAX_ARTICLES_PER_BATCH).map { i ->
            available[(offset + i) % available.size]
        }
    }
}
