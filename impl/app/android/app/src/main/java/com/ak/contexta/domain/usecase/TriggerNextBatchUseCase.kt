package com.ak.contexta.domain.usecase

import android.util.Log
import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 确保有未分配的 READY 批次可用（前置生成）。
 *
 * **关键设计：生成数量与显示数量分离**
 * - [MAX_ARTICLES_PER_BATCH] = 5，每个批次永远固定生成 5 篇文章
 * - 用户选择的 dailyCount 仅在分配批次时（[assignBatchForToday]）写入 [daily_learning.daily_count_snapshot]
 * - 首页显示时从 [daily_learning.daily_count_snapshot] 读取显示数量
 *
 * **流程：**
 * 1. 检查是否有尚未被 [daily_learning] 引用的 READY 批次（匹配当前难度）
 * 2. 有 → 直接返回，无需操作
 * 3. 无 → 检查今天是否已为该难度创建过批次
 * 4. 有今日批次但未完成 → 跳过（Worker 继续）
 * 5. 无 → 创建新批次，触发生成 Worker
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
     * 确保有未来可用的 READY 批次。
     *
     * @param difficulty 用户当前难度等级
     */
    /**
     * 确保有未来可用的 READY 批次。
     *
     * 逻辑：
     * 1. 查找 daily_learning 的 max(ref_batch_date)
     * 2. 查找 user_settings 的难度
     * 3. 检查是否有 generated_on > max(ref_batch_date) 且 difficulty=当前难度的 READY 批次
     *    - 有 → 跳过（已有未来可用批次）
     *    - 无 → 创建新批次并调度 Worker 生成
     *
     * @param difficulty 用户当前难度等级
     */
    suspend operator fun invoke(difficulty: String, dailyCount: Int) {
        val today = timeProvider.todayDateString()
        val maxRefDate = articleRepository.getMaxRefBatchDate() ?: today
        Log.d("TriggerNextBatch", "invoke: difficulty=$difficulty, dailyCount=$dailyCount, today=$today, maxRefDate=$maxRefDate")

        // 1. 检查是否有 generated_on > max(ref_batch_date) 且 difficulty=当前难度的 READY 批次
        //    忽略旧 seed 数据（generated_on 远早于 maxRefDate，不满足 > 条件）
        val unassigned = articleRepository.getUnassignedReadyBatches(difficulty, maxRefDate)
        Log.d("TriggerNextBatch", "getUnassignedReadyBatches($difficulty, >$maxRefDate) => ${unassigned.size} batches")
        if (unassigned.isNotEmpty()) {
            Log.d("TriggerNextBatch", "Found unassigned batches newer than maxRefDate, skipping creation")
            return // 已有比已分配批次更新的可用批次
        }

        // 2. 检查今天是否已为该难度创建过批次（PENDING/GENERATING/READY）。
        //    避免在一天内产生多个同难度批次。
        val existing = articleRepository.getBatchByDifficultyAndDate(difficulty, today)
        Log.d("TriggerNextBatch", "getBatchByDifficultyAndDate($difficulty, $today) => ${existing?.id ?: "null"}")
        if (existing != null) {
            Log.d("TriggerNextBatch", "Batch already exists for today+difficulty, skipping")
            return
        }

        // 3. 没有可用的，创建新批次并调度 Worker
        Log.d("TriggerNextBatch", "Creating new batch for $difficulty")
        val batchId = articleRepository.createBatch(
            difficulty = difficulty,
            generatedOn = today
        )
        Log.d("TriggerNextBatch", "Created batch $batchId")
        val categories = pickCategories(difficulty)
        articleRepository.createArticles(batchId, categories)
        Log.d("TriggerNextBatch", "Created ${categories.size} articles for batch $batchId")
        generationScheduler.scheduleBatchGeneration(batchId)
        Log.d("TriggerNextBatch", "Generation scheduled for batch $batchId")
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
