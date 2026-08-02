package com.ak.contexta.domain.repository

import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleBatch
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.DailyLearningInfo
import com.ak.contexta.domain.model.GenerationError
import kotlinx.coroutines.flow.Flow

interface ArticleRepository {
    fun observeArticles(batchId: Long): Flow<List<Article>>

    suspend fun getArticle(articleId: Long): Article?

    /** Check if pipeline is globally blocked */
    suspend fun isPipelineBlocked(): Boolean

    /** Check and recover blocked pipeline if app version is newer */
    suspend fun recoverIfNewerVersion(currentVersionCode: Int): Boolean

    /**
     * 按难度和生成日期查找批次。
     * 用于防止同一天对同一难度重复创建批次。
     */
    suspend fun getBatchByDifficultyAndDate(difficulty: String, date: String): ArticleBatch?

    /**
     * 查找下一个可用的 READY 批次。
     * - [afterDate] 为 null 时返回第一个 READY 批次（仅首次使用：无 daily_learning 记录）
     * - 否则返回 [generated_on] > [afterDate]（严格晚于已消费批次日期）且尚未被 [daily_learning] 引用的 READY 批次
     *
     * 批次按时间顺序消费：调用方应传入 max(ref_batch_date)，保证不回头分配历史 seed 批次，
     * 避免用户读到旧内容且前置生成被"已有未来批次"跳过。
     */
    suspend fun findNextReadyBatch(difficulty: String, afterDate: String?): ArticleBatch?

    /**
     * 获取所有未被 daily_learning 引用的 READY 批次（按 generated_on 升序）。
     * @param minGeneratedOn 只返回 generated_on >= 此日期的批次
     */
    suspend fun getUnassignedReadyBatches(difficulty: String, minGeneratedOn: String? = null): List<ArticleBatch>

    /** 获取指定阅读日期的已分配批次。 */
    suspend fun getAssignedBatchForDate(readDate: String): ArticleBatch?

    /** 获取所有阅读记录（含关联批次），按日期降序。 */
    suspend fun getAllDailyLearningInfos(): List<DailyLearningInfo>

    /** 获取所有阅读记录中的最大 [refBatchDate]。为 null 表示尚无阅读记录。 */
    suspend fun getMaxRefBatchDate(): String?

    /** 按 ID 获取批次（生成完成通知需要展示批次的生成日期与难度）。 */
    suspend fun getBatchById(batchId: Long): ArticleBatch?

    /**
     * 将批次分配给今天的阅读，插入 daily_learning 记录。
     * @return true 表示成功插入，false 表示今天已有记录
     */
    suspend fun assignBatchForToday(batchId: Long, refBatchDate: String, dailyCount: Int): Boolean

    /** Create a new batch (PENDING) */
    suspend fun createBatch(
        difficulty: String,
        generatedOn: String? = null
    ): Long

    /** Create article rows (PENDING) for a batch */
    suspend fun createArticles(batchId: Long, categories: List<String>)

    /** Get articles in a batch (suspend, for workers) */
    suspend fun getArticles(batchId: Long): List<Article>

    /** Try to claim the batch for generation (CAS) */
    suspend fun claimBatch(batchId: Long): Boolean

    /** Try to claim an article for generation (CAS) */
    suspend fun claimArticle(articleId: Long): Boolean

    /** Mark article as SUCCESS and write paragraphs */
    suspend fun completeArticle(
        articleId: Long,
        title: String,
        paragraphs: List<ArticleParagraph>,
        retryCount: Int
    )

    /** Check if all articles in a batch are SUCCESS */
    suspend fun isBatchComplete(batchId: Long): Boolean

    /** Check if any article in a batch is FATAL */
    suspend fun hasFatalArticle(batchId: Long): Boolean

    /** Mark batch as READY */
    suspend fun markBatchReady(batchId: Long)

    /** Mark batch as BLOCKED. 返回写入的 BATCH 错误流水账 id（无错误详情时为 null）。 */
    suspend fun markBatchBlocked(batchId: Long, reason: String, appVersionCode: Int): Long?

    /**
     * Mark article as FAILED or TIMEOUT.
     * 错误详情（errorCode/errorMessage/errorHelp）和 [retryCount] 快照写入 generation_error_log 流水账。
     * 返回写入的错误流水账 id（无错误详情时为 null），用于告警送达后回写 notified_at。
     */
    suspend fun failArticle(
        articleId: Long,
        status: String,
        errorCode: String? = null,
        errorMessage: String? = null,
        errorHelp: String? = null,
        retryCount: Int = 0
    ): Long?

    /** Mark article as FATAL. 错误详情和重试次数快照写入 generation_error_log 流水账。返回流水账 id。 */
    suspend fun fatalArticle(
        articleId: Long,
        errorCode: String? = null,
        errorMessage: String? = null,
        retryCount: Int = 0
    ): Long?

    /** 回写错误告警的送达时间（幂等）。 */
    suspend fun markErrorNotified(errorLogId: Long)

    /** 回写批次完成通知的送达时间（幂等）。 */
    suspend fun markBatchReadyNotified(batchId: Long)

    /** 获取 [createdAfter]（ISO 时间字符串）之后创建且告警未送达的错误（启动补发用）。 */
    suspend fun getUnnotifiedErrors(createdAfter: String): List<GenerationError>

    /** 获取已 READY 但完成通知未送达的批次（启动补发用）。 */
    suspend fun getReadyBatchesUnnotified(): List<ArticleBatch>

    /** Add reading seconds */
    suspend fun addReadSeconds(articleId: Long, deltaSeconds: Int)

    /** Attempt marking read completed (only if accumulated >= 120s and not yet marked) */
    suspend fun tryMarkReadCompleted(articleId: Long)

    /** Force marking read completed regardless of accumulated time. */
    suspend fun forceMarkReadCompleted(articleId: Long)

    /** Reset orphan GENERATING/TIMEOUT/FAILED articles during app startup reconciliation */
    suspend fun reconcileOrphanArticles()

    /** Get all batches whose status is GENERATING (for startup recovery) */
    suspend fun getGeneratingBatches(): List<ArticleBatch>

    /** Observe latest generation error per article (from generation_error_log, joined with article status) */
    fun observeGenerationErrors(): Flow<List<GenerationError>>

    /** Clear error state and reset article to PENDING for manual retry */
    suspend fun resetArticleForRetry(articleId: Long)
}
