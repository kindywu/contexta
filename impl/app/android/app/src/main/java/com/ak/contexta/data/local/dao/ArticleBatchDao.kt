package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.ArticleBatchEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ArticleBatchDao {
    @Query("SELECT * FROM article_batch WHERE batch_type = :batchType ORDER BY id DESC LIMIT 1")
    fun observeByType(batchType: String): Flow<ArticleBatchEntity?>

    @Query("SELECT * FROM article_batch WHERE batch_type = :batchType ORDER BY id DESC LIMIT 1")
    suspend fun getByType(batchType: String): ArticleBatchEntity?

    /**
     * 获取指定类型的所有批次（含无解锁记录的，供内部逻辑查询）。
     * 首页显示时需自行过滤 unlocked_on IS NOT NULL（见 HomeViewModel）。
     */
    @Query("SELECT * FROM article_batch WHERE batch_type = :batchType ORDER BY id DESC")
    fun observeAllByType(batchType: String): Flow<List<ArticleBatchEntity>>

    /**
     * 同上，仅用于挂起查询。
     */
    @Query("SELECT * FROM article_batch WHERE batch_type = :batchType ORDER BY id DESC")
    suspend fun getAllByType(batchType: String): List<ArticleBatchEntity>

    @Query("SELECT * FROM article_batch WHERE id = :id")
    suspend fun getById(id: Long): ArticleBatchEntity?

    @Query("""
        SELECT * FROM article_batch
        WHERE difficulty_level_snapshot = :difficulty AND generated_on = :date
        ORDER BY id DESC LIMIT 1
    """)
    suspend fun getByDifficultyAndDate(difficulty: String, date: String): ArticleBatchEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(batch: ArticleBatchEntity): Long

    // CAS: only update if still PENDING
    @Query("""
        UPDATE article_batch
        SET status = 'GENERATING', last_updated_at = :now
        WHERE id = :batchId AND status = 'PENDING'
    """)
    suspend fun claimForGeneration(batchId: Long, now: Long): Int

    @Query("""
        UPDATE article_batch
        SET status = :newStatus, last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun updateStatus(batchId: Long, newStatus: String, now: Long)

    @Query("""
        UPDATE article_batch
        SET status = 'CURRENT', unlocked_on = :today, last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun promoteToCurrent(batchId: Long, today: String, now: Long)

    @Query("""
        UPDATE article_batch
        SET status = 'EXPIRED', last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun expire(batchId: Long, now: Long)

    @Query("""
        UPDATE article_batch
        SET batch_type = :batchType, last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun updateBatchType(batchId: Long, batchType: String, now: Long)

    @Query("""
        UPDATE article_batch
        SET daily_count_snapshot = :dailyCount, last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun updateDailyCountSnapshot(batchId: Long, dailyCount: Int, now: Long)

    @Query("""
        UPDATE article_batch
        SET status = 'BLOCKED',
            blocked_reason = :reason,
            blocked_at = :now,
            error_code = :errorCode,
            error_message = :errorMessage,
            last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun markBlocked(
        batchId: Long,
        reason: String?,
        errorCode: String?,
        errorMessage: String?,
        now: Long
    )
}
