package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.ArticleEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ArticleDao {
    @Query("SELECT * FROM article WHERE batch_id = :batchId ORDER BY order_index ASC")
    fun observeByBatch(batchId: Long): Flow<List<ArticleEntity>>

    @Query("SELECT * FROM article WHERE batch_id = :batchId ORDER BY order_index ASC")
    suspend fun getByBatch(batchId: Long): List<ArticleEntity>

    @Query("SELECT * FROM article WHERE id = :id")
    suspend fun getById(id: Long): ArticleEntity?

    @Query("SELECT * FROM article WHERE id = :id")
    fun observeById(id: Long): Flow<ArticleEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(article: ArticleEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(articles: List<ArticleEntity>): List<Long>

    // CAS: claim article for generation
    @Query("""
        UPDATE article
        SET status = 'GENERATING',
            generation_started_at = CASE WHEN status = 'PENDING' THEN :now ELSE generation_started_at END,
            last_retry_at = CASE WHEN status IN ('TIMEOUT', 'FAILED') THEN :now ELSE last_retry_at END
        WHERE id = :articleId AND status IN ('PENDING', 'TIMEOUT', 'FAILED')
    """)
    suspend fun claimForGeneration(articleId: Long, now: String): Int

    @Query("""
        UPDATE article SET status = :status WHERE id = :articleId
    """)
    suspend fun updateStatus(articleId: Long, status: String)

    /**
     * 更新状态并记录重试时间。
     * 错误详情（error_code / error_message / error_help）不再存本表，
     * 由 [com.ak.contexta.data.local.dao.GenerationErrorLogDao] 记录。
     */
    @Query("""
        UPDATE article SET
            status = :status,
            last_retry_at = :now
        WHERE id = :articleId
    """)
    suspend fun updateStatusWithRetryTime(
        articleId: Long,
        status: String,
        now: String
    )

    @Query("""
        UPDATE article SET title = :title, status = 'SUCCESS', generation_completed_at = :now, retry_count = :retryCount WHERE id = :articleId
    """)
    suspend fun markSuccess(articleId: Long, title: String, retryCount: Int, now: String)

    @Query("""
        UPDATE article SET retry_count = :count WHERE id = :articleId
    """)
    suspend fun updateRetryCount(articleId: Long, count: Int)

    @Query("""
        SELECT COUNT(*) FROM article WHERE batch_id = :batchId AND status = 'SUCCESS'
    """)
    suspend fun countSuccessByBatch(batchId: Long): Int

    @Query("""
        SELECT COUNT(*) FROM article WHERE batch_id = :batchId AND status NOT IN ('SUCCESS', 'FATAL', 'GENERATING')
    """)
    suspend fun countPendingByBatch(batchId: Long): Int

    @Query("""
        SELECT COUNT(*) FROM article WHERE batch_id = :batchId AND status = 'FATAL'
    """)
    suspend fun countFatalByBatch(batchId: Long): Int

    @Query("""
        SELECT COUNT(*) FROM article WHERE batch_id = :batchId
    """)
    suspend fun countByBatch(batchId: Long): Int

    @Query("""
        UPDATE article SET status = 'PENDING', retry_count = 0 WHERE status = 'GENERATING' AND batch_id = :batchId
    """)
    suspend fun resetOrphanGenerating(batchId: Long)

    /** 重置所有卡在 GENERATING 状态的文章回 PENDING（应用启动时调用）。 */
    @Query("""
        UPDATE article SET status = 'PENDING', retry_count = 0, generation_started_at = NULL
        WHERE status = 'GENERATING'
    """)
    suspend fun resetAllGenerating()

    /**
     * 重置所有 TIMEOUT / FAILED 文章回 PENDING（应用启动时调用）。
     * 这些文章因为协程超时取消等问题被标记为错误状态但从未重试，
     * 与 GENERATING 一样需要启动恢复。
     */
    @Query("""
        UPDATE article SET status = 'PENDING', retry_count = 0, last_retry_at = NULL
        WHERE status IN ('TIMEOUT', 'FAILED')
    """)
    suspend fun resetAllTimedOutAndFailed()

    @Query("""
        UPDATE article SET status = 'PENDING', retry_count = 0, last_retry_at = NULL
        WHERE id = :articleId
    """)
    suspend fun resetForRetry(articleId: Long)

    @Query("""
        UPDATE article SET accumulated_read_seconds = accumulated_read_seconds + :deltaSeconds WHERE id = :articleId
    """)
    suspend fun addReadSeconds(articleId: Long, deltaSeconds: Int)

    @Query("""
        UPDATE article SET read_completed_at = :now WHERE id = :articleId AND accumulated_read_seconds >= 120 AND read_completed_at IS NULL
    """)
    suspend fun markReadCompleted(articleId: Long, now: String)

    @Query("""
        UPDATE article SET read_completed_at = :now WHERE id = :articleId AND read_completed_at IS NULL
    """)
    suspend fun forceMarkReadCompleted(articleId: Long, now: String)
}
