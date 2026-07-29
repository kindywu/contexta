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

    @Query("SELECT * FROM article_batch WHERE id = :id")
    suspend fun getById(id: Long): ArticleBatchEntity?

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
        SET status = 'INVALIDATED', last_updated_at = :now
        WHERE id = :batchId
    """)
    suspend fun invalidate(batchId: Long, now: Long)
}
