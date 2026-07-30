package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.BatchType
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 确保 NEXT 批次存在且与当前难度匹配。
 *
 * **关键设计：生成数量与显示数量分离**
 * - [MAX_ARTICLES_PER_BATCH] = 5，每个批次永远固定生成 5 篇文章
 * - [dailyCount] 仅作为 [ArticleBatch.dailyCountSnapshot] 保存到数据库
 * - 首页显示时 CURRENT 批次用当前设置，EXPIRED 用 snapshot（见 [HomeViewModel]）
 *
 * **难度变更时的批次复用逻辑：**
 * 1. 如果当前 NEXT 批次的难度与新难度不同 → 废弃旧 NEXT（batch_type=EXPIRED）
 * 2. 在已废弃的 EXPIRED 批次中查找是否有已完成且难度匹配的
 *    → 找到则复用（batch_type=NEXT，更新 daily_count_snapshot），无需 Worker
 *    → 未找到则创建新 NEXT 批次 + 调度 Worker 生成
 */
@Singleton
class TriggerNextBatchUseCase @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val generationScheduler: BackgroundWorkScheduler,
    private val timeProvider: TimeProvider
) {
    companion object {
        /**
         * 每批固定生成的最大文章数。
         * 无论用户选择每天看 1~5 篇，系统总是生成 5 篇。
         * 用户选择的篇数仅控制首页显示数量，不影响生成。
         */
        const val MAX_ARTICLES_PER_BATCH = 5

        val CONTENT_CATEGORIES = mapOf(
            "LOW" to listOf("DAILY_CONVERSATION", "SCENE_DESCRIPTION", "SIMPLE_STORY"),
            "MEDIUM" to listOf("NEWS", "EXPOSITORY", "ARGUMENTATIVE", "PERSONAL_ESSAY"),
            "HIGH" to listOf("ACADEMIC_EXCERPT", "DEBATE_SPEECH", "LEGAL_DOCUMENT", "ART_CRITICISM", "CLASSIC_NOVEL_EXCERPT")
        )
    }

    /**
     * 确保 NEXT 批次存在且难度匹配。
     *
     * @param difficulty 用户当前难度等级
     * @param dailyCount 用户当前每日篇数（更新到 snapshot）
     */
    suspend operator fun invoke(difficulty: String, dailyCount: Int) {
        // 1. 检查现有 NEXT 批次
        val existingNext = articleRepository.getNextBatch()
        if (existingNext != null && existingNext.status != BatchStatus.EXPIRED) {
            if (existingNext.difficultyLevelSnapshot == difficulty) {
                return // 难度相同，无需变更
            }
            // 难度不同：废弃当前 NEXT 批次
            articleRepository.expireBatch(existingNext.id)
        }

        // 2. 查找已废弃的批次中是否有可复用的（难度匹配且文章全部生成完成）
        val expired = articleRepository.getExpiredBatches()
        val reusable = expired.firstOrNull { batch ->
            batch.difficultyLevelSnapshot == difficulty &&
            articleRepository.isBatchComplete(batch.id)
        }

        if (reusable != null) {
            // 复用已有批次：改回 NEXT，更新 snapshot
            articleRepository.reactivateBatch(reusable.id, dailyCount)
            return
        }

        // 3. 没有可复用的，创建新批次并调度 Worker
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
