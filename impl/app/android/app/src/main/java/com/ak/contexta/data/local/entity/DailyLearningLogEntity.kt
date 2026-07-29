package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "daily_learning_log")
data class DailyLearningLogEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "log_date")
    val logDate: String, // ISO date "2026-07-29"
    @ColumnInfo(name = "articles_read")
    val articlesRead: Int = 0,
    @ColumnInfo(name = "words_added")
    val wordsAdded: Int = 0,
    @ColumnInfo(name = "seconds_spent")
    val secondsSpent: Int = 0
)
