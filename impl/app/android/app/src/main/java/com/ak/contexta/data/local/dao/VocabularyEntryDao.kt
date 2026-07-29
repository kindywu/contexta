package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.VocabularyEntryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface VocabularyEntryDao {
    @Query("""
        SELECT * FROM vocabulary_entry
        WHERE word_id = :wordId AND deleted_at IS NULL
        ORDER BY instance_number DESC LIMIT 1
    """)
    suspend fun getActiveByWord(wordId: Long): VocabularyEntryEntity?

    @Query("""
        SELECT * FROM vocabulary_entry
        WHERE deleted_at IS NULL AND status != 'MASTERED'
        ORDER BY id ASC
    """)
    fun observeActive(): Flow<List<VocabularyEntryEntity>>

    @Query("""
        SELECT * FROM vocabulary_entry
        WHERE deleted_at IS NULL AND status != 'MASTERED'
        ORDER BY id ASC
    """)
    suspend fun getActive(): List<VocabularyEntryEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entry: VocabularyEntryEntity): Long

    @Query("""
        SELECT COALESCE(MAX(instance_number), 0) + 1 FROM vocabulary_entry WHERE word_id = :wordId
    """)
    suspend fun nextInstanceNumber(wordId: Long): Int

    @Query("""
        UPDATE vocabulary_entry
        SET status = :status, correct_review_streak = correct_review_streak + 1
        WHERE id = :id AND deleted_at IS NULL
    """)
    suspend fun markCorrectReview(id: Long, status: String)

    @Query("""
        UPDATE vocabulary_entry
        SET status = 'MASTERED', mastered_at = :now, correct_review_streak = correct_review_streak + 1
        WHERE id = :id AND deleted_at IS NULL
    """)
    suspend fun markMastered(id: Long, now: Long)

    @Query("""
        UPDATE vocabulary_entry
        SET correct_review_streak = 0
        WHERE id = :id AND deleted_at IS NULL
    """)
    suspend fun resetStreak(id: Long)

    @Query("""
        UPDATE vocabulary_entry
        SET deleted_at = :now, deleted_reason = :reason
        WHERE id = :id AND deleted_at IS NULL
    """)
    suspend fun softDelete(id: Long, reason: String, now: Long)

    @Query("SELECT * FROM vocabulary_entry WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): VocabularyEntryEntity?

    @Query("SELECT COUNT(DISTINCT word_id) FROM vocabulary_entry WHERE deleted_at IS NULL")
    suspend fun countDistinctWords(): Int
}
