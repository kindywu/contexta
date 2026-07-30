package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.repository.ArticleRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 为首次使用创建初始批次（onboarding 完成后或首次打开 app 时）。
 *
 * 创建批次 → 创建文章 → 分配到今天的 daily_learning → 调用方触发生成 Worker。
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
            difficulty = difficulty
        )
        val categories = triggerNextBatch.pickCategories(difficulty)
        articleRepository.createArticles(batchId, categories)

        // 立即将当前批次分配到今天的 daily_learning
        // 这样用户打开首页时能看到等待状态
        articleRepository.assignBatchForToday(
            batchId = batchId,
            refBatchDate = java.time.LocalDate.now().toString(),
            dailyCount = dailyCount
        )

        return batchId
    }
}
