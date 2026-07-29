package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.WordEntity

@Dao
interface WordDao {
    @Query("SELECT * FROM word WHERE spelling_normalized = :normalized")
    suspend fun getByNormalized(normalized: String): WordEntity?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(word: WordEntity): Long

    @Query("SELECT * FROM word WHERE id = :id")
    suspend fun getById(id: Long): WordEntity?

    @Query("SELECT * FROM word WHERE id IN (:ids)")
    suspend fun getByIds(ids: List<Long>): List<WordEntity>
}
