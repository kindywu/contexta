package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "article",
    foreignKeys = [
        ForeignKey(
            entity = ArticleBatchEntity::class,
            parentColumns = ["id"],
            childColumns = ["batch_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("batch_id")]
)
data class ArticleEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "batch_id")
    val batchId: Long,
    @ColumnInfo(name = "order_index")
    val orderIndex: Int,
    @ColumnInfo(name = "content_category")
    val contentCategory: String,
    @ColumnInfo(name = "title")
    val title: String? = null, // populated after generation succeeds
    @ColumnInfo(name = "status")
    val status: String = "PENDING", // PENDING | GENERATING | SUCCESS | TIMEOUT | FAILED | FATAL
    @ColumnInfo(name = "generation_started_at")
    val generationStartedAt: Long? = null,
    @ColumnInfo(name = "generation_completed_at")
    val generationCompletedAt: Long? = null,
    @ColumnInfo(name = "retry_count")
    val retryCount: Int = 0,
    @ColumnInfo(name = "accumulated_read_seconds")
    val accumulatedReadSeconds: Int = 0,
    @ColumnInfo(name = "read_completed_at")
    val readCompletedAt: Long? = null,
    @ColumnInfo(name = "last_retry_at")
    val lastRetryAt: Long? = null,
    @ColumnInfo(name = "error_code")
    val errorCode: String? = null,
    @ColumnInfo(name = "error_message")
    val errorMessage: String? = null,
    @ColumnInfo(name = "error_help")
    val errorHelp: String? = null,
    @ColumnInfo(name = "max_retries")
    val maxRetries: Int = 3,
    @ColumnInfo(name = "next_retry_at")
    val nextRetryAt: Long? = null
)
