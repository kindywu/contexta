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
    suspend fun claimForGeneration(articleId: Long, now: Long): Int

    @Query("""
        UPDATE article SET status = :status WHERE id = :articleId
    """)
    suspend fun updateStatus(articleId: Long, status: String)

    @Query("""
        UPDATE article SET
            status = :status,
            error_code = :errorCode,
            error_message = :errorMessage,
            error_help = :errorHelp,
            last_retry_at = :now
        WHERE id = :articleId
    """)
    suspend fun updateStatusWithError(
        articleId: Long,
        status: String,
        errorCode: String?,
        errorMessage: String?,
        errorHelp: String?,
        now: Long
    )

    @Query("""
        UPDATE article SET
            status = 'FATAL',
            error_code = :errorCode,
            error_message = :errorMessage,
            last_retry_at = :now
        WHERE id = :articleId
    """)
    suspend fun markFatal(
        articleId: Long,
        errorCode: String?,
        errorMessage: String?,
        now: Long
    )

    @Query("""
        UPDATE article SET title = :title, status = 'SUCCESS', generation_completed_at = :now, retry_count = :retryCount WHERE id = :articleId
    """)
    suspend fun markSuccess(articleId: Long, title: String, retryCount: Int, now: Long)

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

    @Query("""
        SELECT * FROM article WHERE error_code IS NOT NULL ORDER BY last_retry_at DESC
    """)
    fun observeGenerationErrors(): Flow<List<ArticleEntity>>

    @Query("""
        UPDATE article SET status = 'PENDING', error_code = NULL, error_message = NULL, error_help = NULL, retry_count = 0, last_retry_at = NULL
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
    suspend fun markReadCompleted(articleId: Long, now: Long)

    @Query("""
        UPDATE article SET read_completed_at = :now WHERE id = :articleId AND read_completed_at IS NULL
    """)
    suspend fun forceMarkReadCompleted(articleId: Long, now: Long)
}
