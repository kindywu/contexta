package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.GenerationPipelineStatusEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface GenerationPipelineStatusDao {
    @Query("SELECT * FROM generation_pipeline_status WHERE id = 1")
    fun observe(): Flow<GenerationPipelineStatusEntity?>

    @Query("SELECT * FROM generation_pipeline_status WHERE id = 1")
    suspend fun get(): GenerationPipelineStatusEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(status: GenerationPipelineStatusEntity)

    @Query("UPDATE generation_pipeline_status SET is_blocked = 0 WHERE id = 1")
    suspend fun clearBlocked()

    @Query("""
        UPDATE generation_pipeline_status
        SET is_blocked = 1, blocked_reason = :reason, blocked_at = :now, blocked_app_version_code = :appVersionCode
        WHERE id = 1
    """)
    suspend fun setBlocked(reason: String, now: String, appVersionCode: Int)
}
