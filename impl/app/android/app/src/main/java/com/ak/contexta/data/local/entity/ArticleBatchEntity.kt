package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.ak.contexta.data.local.ContextaTypeConverters

@Entity(
    tableName = "article_batch",
    indices = [
        Index(value = ["generated_on"]),
        Index(
            value = ["difficulty_level_snapshot", "generated_on"],
            unique = true
        )
    ]
)
data class ArticleBatchEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "status")
    val status: String = "PENDING", // PENDING | GENERATING | READY | CURRENT | BLOCKED
    @ColumnInfo(name = "difficulty_level_snapshot")
    val difficultyLevelSnapshot: String,
    @ColumnInfo(name = "generated_on")
    val generatedOn: String, // ISO date
    @ColumnInfo(name = "last_updated_at")
    val lastUpdatedAt: String = ContextaTypeConverters.currentDateTimeString(),
    @ColumnInfo(name = "blocked_reason")
    val blockedReason: String? = null,
    @ColumnInfo(name = "blocked_at")
    val blockedAt: String? = null
)
