package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "learning_stats_summary")
data class LearningStatsSummaryEntity(
    @PrimaryKey
    val id: Int = 1, // singleton, always 1
    @ColumnInfo(name = "total_articles_read")
    val totalArticlesRead: Int = 0,
    @ColumnInfo(name = "total_words_added")
    val totalWordsAdded: Int = 0,
    @ColumnInfo(name = "total_words_mastered")
    val totalWordsMastered: Int = 0,
    @ColumnInfo(name = "total_learning_days")
    val totalLearningDays: Int = 0,
    @ColumnInfo(name = "current_streak")
    val currentStreak: Int = 0,
    @ColumnInfo(name = "longest_streak")
    val longestStreak: Int = 0,
    @ColumnInfo(name = "last_active_date")
    val lastActiveDate: String? = null // ISO date
)
