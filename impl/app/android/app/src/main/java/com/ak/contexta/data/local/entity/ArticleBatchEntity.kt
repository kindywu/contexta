package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "article_batch")
data class ArticleBatchEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "batch_type")
    val batchType: String, // CURRENT | NEXT
    @ColumnInfo(name = "status")
    val status: String = "PENDING", // PENDING | GENERATING | READY | CURRENT | EXPIRED | BLOCKED
    @ColumnInfo(name = "difficulty_level_snapshot")
    val difficultyLevelSnapshot: String,
    @ColumnInfo(name = "daily_count_snapshot")
    val dailyCountSnapshot: Int,
    @ColumnInfo(name = "generated_on")
    val generatedOn: String? = null, // ISO date
    @ColumnInfo(name = "unlocked_on")
    val unlockedOn: String? = null, // ISO date, set when promoted to CURRENT
    @ColumnInfo(name = "last_updated_at")
    val lastUpdatedAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "error_code")
    val errorCode: String? = null,
    @ColumnInfo(name = "error_message")
    val errorMessage: String? = null,
    @ColumnInfo(name = "blocked_reason")
    val blockedReason: String? = null,
    @ColumnInfo(name = "blocked_at")
    val blockedAt: Long? = null
)
