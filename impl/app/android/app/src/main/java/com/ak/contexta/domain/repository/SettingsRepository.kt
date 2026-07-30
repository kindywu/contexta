package com.ak.contexta.domain.repository

import com.ak.contexta.domain.model.UserSettings
import kotlinx.coroutines.flow.Flow

interface SettingsRepository {
    fun observeSettings(): Flow<UserSettings?>

    suspend fun getSettings(): UserSettings?

    suspend fun isOnboarded(): Boolean

    suspend fun completeOnboarding(level: String, dailyCount: Int)

    suspend fun updateLevel(level: String)

    suspend fun updateDailyArticleCount(newCount: Int): Boolean

    suspend fun updateTranslationMode(mode: String)

    suspend fun updateMasteryThreshold(n: Int)

    suspend fun updateAutoPlayAudio(enabled: Boolean)
}
