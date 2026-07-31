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
    val generationStartedAt: String? = null,
    @ColumnInfo(name = "generation_completed_at")
    val generationCompletedAt: String? = null,
    @ColumnInfo(name = "retry_count")
    val retryCount: Int = 0,
    @ColumnInfo(name = "accumulated_read_seconds")
    val accumulatedReadSeconds: Int = 0,
    @ColumnInfo(name = "read_completed_at")
    val readCompletedAt: String? = null,
    @ColumnInfo(name = "last_retry_at")
    val lastRetryAt: String? = null,
    @ColumnInfo(name = "max_retries")
    val maxRetries: Int = 3,
    @ColumnInfo(name = "next_retry_at")
    val nextRetryAt: String? = null
)
