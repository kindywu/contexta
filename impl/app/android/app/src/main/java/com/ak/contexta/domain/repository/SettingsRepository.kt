package com.ak.contexta.domain.repository

import com.ak.contexta.data.local.ContextaTypeConverters
import com.ak.contexta.data.local.dao.ConfigChangeLogDao
import com.ak.contexta.data.local.dao.UserSettingsDao
import com.ak.contexta.data.local.entity.ConfigChangeLogEntity
import com.ak.contexta.data.local.entity.UserSettingsEntity
import com.ak.contexta.domain.model.ArticleBatch
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SettingsRepository @Inject constructor(
    private val settingsDao: UserSettingsDao,
    private val configChangeLogDao: ConfigChangeLogDao,
    private val articleRepository: ArticleRepository
) {
    fun observeSettings(): Flow<UserSettingsEntity?> = settingsDao.observe()

    suspend fun getSettings(): UserSettingsEntity? = settingsDao.get()

    suspend fun isOnboarded(): Boolean = settingsDao.get()?.isOnboarded == true

    suspend fun completeOnboarding(level: String, dailyCount: Int) {
        val existing = settingsDao.get()
        settingsDao.upsert(
            (existing ?: UserSettingsEntity()).copy(
                isOnboarded = true,
                difficultyLevel = level,
                dailyArticleCount = dailyCount
            )
        )
    }

    suspend fun updateLevel(level: String) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(difficultyLevel = level))
    }

    /**
     * Update daily article count with frequency limit check.
     * Returns true if the change was applied.
     */
    suspend fun updateDailyArticleCount(newCount: Int): Boolean {
        val existing = settingsDao.get() ?: return false
        if (newCount == existing.dailyArticleCount) return false // no change, no limit consumed
        if (!canModifyDailyCount()) return false

        val now = System.currentTimeMillis()
        // Record the change
        configChangeLogDao.insert(
            ConfigChangeLogEntity(
                fieldName = "daily_article_count",
                oldValue = existing.dailyArticleCount.toString(),
                newValue = newCount.toString(),
                createdAt = now
            )
        )

        val oldCount = existing.dailyArticleCount
        settingsDao.upsert(existing.copy(dailyArticleCount = newCount))

        // If a NEXT batch exists and hasn't been unlocked, invalidate it
        articleRepository.onDailyCountChanged(oldCount, newCount)

        return true
    }

    suspend fun canModifyDailyCount(): Boolean {
        val now = System.currentTimeMillis()
        val todayStart = getDayStartMillis(now)
        val todayEnd = todayStart + 86_400_000L
        val monthStart = getMonthStartMillis(now)
        val monthEnd = getNextMonthStartMillis(now)

        val todayCount = configChangeLogDao.countToday("daily_article_count", todayStart, todayEnd)
        if (todayCount >= 1) return false

        val monthCount = configChangeLogDao.countThisMonth("daily_article_count", monthStart, monthEnd)
        if (monthCount >= 3) return false

        return true
    }

    suspend fun updateTranslationMode(mode: String) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(translationDisplayMode = mode))
    }

    suspend fun updateMasteryThreshold(n: Int) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(masteryThresholdN = n.coerceIn(1, 5)))
    }

    suspend fun updateAutoPlayAudio(enabled: Boolean) {
        val existing = settingsDao.get() ?: return
        settingsDao.upsert(existing.copy(autoPlayAudio = enabled))
    }

    private fun getDayStartMillis(now: Long): Long {
        val date = ContextaTypeConverters.timestampToDateString(now)
        return java.time.LocalDate.parse(date)
            .atStartOfDay(java.time.ZoneId.of("Asia/Shanghai"))
            .toInstant()
            .toEpochMilli()
    }

    private fun getMonthStartMillis(now: Long): Long {
        val date = ContextaTypeConverters.timestampToDateString(now)
        val monthStart = date.take(7) + "-01"
        return java.time.LocalDate.parse(monthStart)
            .atStartOfDay(java.time.ZoneId.of("Asia/Shanghai"))
            .toInstant()
            .toEpochMilli()
    }

    private fun getNextMonthStartMillis(now: Long): Long {
        val date = ContextaTypeConverters.timestampToDateString(now)
        val localDate = java.time.LocalDate.parse(date)
        val nextMonth = localDate.plusMonths(1).withDayOfMonth(1)
        return nextMonth
            .atStartOfDay(java.time.ZoneId.of("Asia/Shanghai"))
            .toInstant()
            .toEpochMilli()
    }
}
