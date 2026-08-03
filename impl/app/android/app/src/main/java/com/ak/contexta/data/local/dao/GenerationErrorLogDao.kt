package com.ak.contexta.data.local.dao

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.GenerationErrorLogEntity
import kotlinx.coroutines.flow.Flow

/** 错误日志 + 实体表状态投影（用于首页判断 canRetry）。 */
data class GenerationErrorWithStatus(
    @Embedded val error: GenerationErrorLogEntity,
    @ColumnInfo(name = "article_status")
    val articleStatus: String?
)

@Dao
interface GenerationErrorLogDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(error: GenerationErrorLogEntity): Long

    /**
     * 观察所有 ARTICLE 错误，每篇实体只取最新一条（按创建时间倒序）。
     * LEFT JOIN article 投影当前状态；实体已删除时 status 为 null。
     */
    @Query("""
        SELECT e.*, a.status AS article_status
        FROM generation_error_log e
        LEFT JOIN article a ON a.id = e.entity_id
        WHERE e.entity_type = 'ARTICLE'
          AND e.id = (
              SELECT MAX(e2.id) FROM generation_error_log e2
              WHERE e2.entity_type = 'ARTICLE' AND e2.entity_id = e.entity_id
          )
        ORDER BY e.created_at DESC
    """)
    fun observeArticleErrors(): Flow<List<GenerationErrorWithStatus>>

    /** 查询某实体的全部错误历史（按时间倒序）。 */
    @Query("""
        SELECT * FROM generation_error_log
        WHERE entity_type = :entityType AND entity_id = :entityId
        ORDER BY created_at DESC
    """)
    suspend fun getByEntity(entityType: String, entityId: Long): List<GenerationErrorLogEntity>

    /** 获取 [createdAfter] 之后创建且告警未送达的错误（启动时补发飞书告警）。 */
    @Query("""
        SELECT * FROM generation_error_log
        WHERE notified_at IS NULL AND created_at >= :createdAfter
        ORDER BY created_at ASC
    """)
    suspend fun getUnnotified(createdAfter: String): List<GenerationErrorLogEntity>

    /** 回写告警送达时间（幂等：只写一次，避免重复补发）。 */
    @Query("""
        UPDATE generation_error_log
        SET notified_at = :at
        WHERE id = :id AND notified_at IS NULL
    """)
    suspend fun markNotified(id: Long, at: Long)
}
