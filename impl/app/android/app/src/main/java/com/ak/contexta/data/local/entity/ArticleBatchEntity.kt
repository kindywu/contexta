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
    /**
     * 该批次在首页展示的文章数量上限（非生成数量）。
     * 生成数量固定为 MAX_ARTICLES_PER_BATCH = 5，不存 DB。
     * 此字段记录批次创建时用户的 daily_article_count 设置，
     * 仅用于首页显示过滤（GetHomeArticlesUseCase.take(displayLimit)）。
     * 修改篇数设置不影响已有批次的此值。
     */
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
