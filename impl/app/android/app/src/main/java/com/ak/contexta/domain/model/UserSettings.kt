package com.ak.contexta.domain.model

/**
 * Domain model for user settings.
 * Mirrors UserSettingsEntity but belongs to the domain layer.
 */
data class UserSettings(
    val id: Int = 1,
    val isOnboarded: Boolean = false,
    val difficultyLevel: String = "MEDIUM",     // LOW | MEDIUM | HIGH
    val dailyArticleCount: Int = 3,
    val translationDisplayMode: String = "FULL", // FULL | BLURRED | HIDDEN
    val masteryThresholdN: Int = 1,
    val autoPlayAudio: Boolean = false
)
