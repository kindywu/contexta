package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.ArticleBatchEntity

@Dao
interface ArticleBatchDao {
    @Query("SELECT * FROM article_batch WHERE id = :id")
    suspend fun getById(id: Long): ArticleBatchEntity?

    @Query("""
        SELECT * FROM article_batch
        WHERE difficulty_level_snapshot = :difficulty AND generated_on = :date
        ORDER BY id DESC LIMIT 1
    """)
    suspend fun getByDifficultyAndDate(difficulty: String, date: String): ArticleBatchEntity?

    /**
     * 查找下一个可用的 READY 批次。
     * - [afterDate] 为 null 时返回第一个 READY 批次（仅首次使用：无 daily_learning 记录）
     * - 否则返回 [generated_on] > [afterDate]（严格晚于已消费批次日期）且尚未被 [daily_learning] 引用的 READY 批次
     *
     * **消费顺序语义**：批次按时间顺序消费，已消费日期（max ref_batch_date）之前的批次不再回头分配。
     * 例如 seed 历史批次（generated_on=03-29）在用户已消费 03-29 批次后不再被分配，
     * 即使它是该难度下最旧的 READY 批次——否则用户会重复读到旧种子内容，且
     * TriggerNextBatchUseCase 会因"已有未来批次"而跳过新批次生成。
     */
    @Query("""
        SELECT * FROM article_batch
        WHERE status = 'READY'
          AND difficulty_level_snapshot = :difficulty
          AND (generated_on > :afterDate OR :afterDate IS NULL)
          AND id NOT IN (SELECT ref_batch_id FROM daily_learning)
        ORDER BY generated_on ASC
        LIMIT 1
    """)
    suspend fun findNextReadyBatch(difficulty: String, afterDate: String?): ArticleBatchEntity?

    /**
     * 获取指定难度的所有 READY 批次（含可能已被 daily_learning 引用的）。
     */
    @Query("""
        SELECT * FROM article_batch
        WHERE status = 'READY' AND difficulty_level_snapshot = :difficulty
        ORDER BY generated_on ASC
    """)
    suspend fun getReadyBatches(difficulty: String): List<ArticleBatchEntity>

    /**
     * 获取指定难度的所有未被 daily_learning 引用的 READY 批次。
     * @param minGeneratedOn 只返回 generated_on > 此日期的批次（忽略旧 seed 数据和已分配批次同期的数据）
     */
    @Query("""
        SELECT * FROM article_batch
        WHERE status = 'READY'
          AND difficulty_level_snapshot = :difficulty
          AND generated_on > :minGeneratedOn
          AND id NOT IN (SELECT ref_batch_id FROM daily_learning)
        ORDER BY generated_on ASC
    """)
    suspend fun getUnassignedReadyBatches(difficulty: String, minGeneratedOn: String): List<ArticleBatchEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(batch: ArticleBatchEntity): Long

    // CAS: only update if still PENDING
    @Query("""
        UPDATE article_batch
        SET status = 'GENERATING', last_updated_at = :now
        WHERE id = :batchId AND status = 'PENDING'
    """)
    suspend fun claimForGeneration(batchId: Long, now: String): Int

    @Query("""
        UPDATE article_batch
        SET status = :newStatus, last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun updateStatus(batchId: Long, newStatus: String, now: String)

    @Query("""
        UPDATE article_batch
        SET status = 'BLOCKED',
            blocked_reason = :reason,
            blocked_at = :now,
            last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun markBlocked(
        batchId: Long,
        reason: String?,
        now: String
    )

    /** 获取所有 GENERATING 状态的批次（用于启动恢复：重新调度卡死的批次）。 */
    @Query("""
        SELECT * FROM article_batch WHERE status = 'GENERATING'
    """)
    suspend fun getGeneratingBatches(): List<ArticleBatchEntity>

    /** 将所有 GENERATING 状态的批次重置为 PENDING（启动恢复用）。 */
    @Query("""
        UPDATE article_batch SET status = 'PENDING'
        WHERE status = 'GENERATING'
    """)
    suspend fun resetAllGeneratingBatches()
}
