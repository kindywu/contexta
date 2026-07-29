package com.ak.contexta.domain.model

data class DailyStats(
    val totalArticlesRead: Int,
    val totalWordsAdded: Int,
    val totalWordsMastered: Int,
    val totalLearningDays: Int,
    val currentStreak: Int,
    val longestStreak: Int,
    val lastActiveDate: String?
)
