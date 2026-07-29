package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "user_settings")
data class UserSettingsEntity(
    @PrimaryKey
    val id: Int = 1, // singleton, always 1
    @ColumnInfo(name = "is_onboarded")
    val isOnboarded: Boolean = false,
    @ColumnInfo(name = "difficulty_level")
    val difficultyLevel: String = "MEDIUM", // LOW | MEDIUM | HIGH
    @ColumnInfo(name = "daily_article_count")
    val dailyArticleCount: Int = 3,
    @ColumnInfo(name = "translation_display_mode")
    val translationDisplayMode: String = "FULL", // FULL | BLURRED | HIDDEN
    @ColumnInfo(name = "mastery_threshold_n")
    val masteryThresholdN: Int = 1,
    @ColumnInfo(name = "auto_play_audio")
    val autoPlayAudio: Boolean = false
)
