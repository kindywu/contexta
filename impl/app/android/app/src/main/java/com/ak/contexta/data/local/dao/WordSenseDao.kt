package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.WordSenseEntity

@Dao
interface WordSenseDao {
    @Query("SELECT * FROM word_sense WHERE word_id = :wordId ORDER BY order_index ASC")
    suspend fun getByWord(wordId: Long): List<WordSenseEntity>

    @Query("SELECT * FROM word_sense WHERE word_id = :wordId ORDER BY order_index ASC LIMIT 1")
    suspend fun getPrimarySense(wordId: Long): WordSenseEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(senses: List<WordSenseEntity>): List<Long>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(sense: WordSenseEntity): Long
}
