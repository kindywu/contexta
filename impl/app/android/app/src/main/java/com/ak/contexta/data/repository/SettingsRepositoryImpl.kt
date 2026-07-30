package com.ak.contexta.data.repository

import com.ak.contexta.data.local.dao.UserSettingsDao
import com.ak.contexta.data.local.entity.UserSettingsEntity
import com.ak.contexta.domain.model.UserSettings
import com.ak.contexta.domain.repository.SettingsRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SettingsRepositoryImpl @Inject constructor(
    private val settingsDao: UserSettingsDao,
) : SettingsRepository {

    override fun observeSettings(): Flow<UserSettings?> =
        settingsDao.observe().map { it?.toModel() }

    override suspend fun getSettings(): UserSettings? =
        settingsDao.get()?.toModel()

    override suspend fun isOnboarded(): Boolean =
        settingsDao.get()?.isOnboarded == true

    override suspend fun completeOnboarding(level: String, dailyCount: Int) {
        val existing = settingsDao.get()
        settingsDao.upsert(
            (existing ?: UserSettingsEntity()).copy(
                isOnboarded = true,
                difficultyLevel = level,
                dailyArticleCount = dailyCount
            )
        )
    }

    override suspend fun updateLevel(level: String) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(difficultyLevel = level))
    }

    override suspend fun updateDailyArticleCount(newCount: Int): Boolean {
        val existing = settingsDao.get() ?: return false
        if (newCount == existing.dailyArticleCount) return false
        if (newCount < 1 || newCount > 5) return false
        settingsDao.upsert(existing.copy(dailyArticleCount = newCount))
        return true
    }

    override suspend fun updateTranslationMode(mode: String) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(translationDisplayMode = mode))
    }

    override suspend fun updateMasteryThreshold(n: Int) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(masteryThresholdN = n.coerceIn(1, 5)))
    }

    override suspend fun updateAutoPlayAudio(enabled: Boolean) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(autoPlayAudio = enabled))
    }

    private fun UserSettingsEntity.toModel() = UserSettings(
        id = id,
        isOnboarded = isOnboarded,
        difficultyLevel = difficultyLevel,
        dailyArticleCount = dailyArticleCount,
        translationDisplayMode = translationDisplayMode,
        masteryThresholdN = masteryThresholdN,
        autoPlayAudio = autoPlayAudio
    )
}
