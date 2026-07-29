package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.ExampleSentenceEntity

@Dao
interface ExampleSentenceDao {
    @Query("SELECT * FROM example_sentence WHERE word_sense_id = :senseId ORDER BY order_index ASC")
    suspend fun getBySense(senseId: Long): List<ExampleSentenceEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(sentences: List<ExampleSentenceEntity>)
}
