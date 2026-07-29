package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.LearningStatsSummaryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface LearningStatsSummaryDao {
    @Query("SELECT * FROM learning_stats_summary WHERE id = 1")
    fun observe(): Flow<LearningStatsSummaryEntity?>

    @Query("SELECT * FROM learning_stats_summary WHERE id = 1")
    suspend fun get(): LearningStatsSummaryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(stats: LearningStatsSummaryEntity)
}
