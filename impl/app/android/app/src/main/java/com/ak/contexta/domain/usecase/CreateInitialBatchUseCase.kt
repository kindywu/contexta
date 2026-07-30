package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.model.BatchType
import com.ak.contexta.domain.repository.ArticleRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 为首次使用（onboarding 完成后）创建 CURRENT 批次。
 * 从 [GenerationManager.startInitialGeneration] 提取。
 */
@Singleton
class CreateInitialBatchUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val triggerNextBatch: TriggerNextBatchUseCase
) {
    /**
     * 创建初始批次并编排文章生成。
     * @return 创建的 batch ID（调用方可用它触发 WorkManager）
     */
    suspend operator fun invoke(difficulty: String, dailyCount: Int): Long {
        val batchId = articleRepository.createBatch(
            batchType = BatchType.CURRENT.value,
            difficulty = difficulty,
            dailyCount = dailyCount
        )
        val categories = triggerNextBatch.pickCategories(difficulty)
        articleRepository.createArticles(batchId, categories)
        return batchId
    }
}
