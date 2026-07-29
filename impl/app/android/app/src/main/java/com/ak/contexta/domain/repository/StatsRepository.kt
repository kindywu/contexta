package com.ak.contexta.domain.repository

import com.ak.contexta.data.local.ContextaTypeConverters
import com.ak.contexta.data.local.dao.DailyLearningLogDao
import com.ak.contexta.data.local.dao.LearningStatsSummaryDao
import com.ak.contexta.data.local.entity.LearningStatsSummaryEntity
import com.ak.contexta.domain.model.DailyStats
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StatsRepository @Inject constructor(
    private val dailyLearningLogDao: DailyLearningLogDao,
    private val learningStatsSummaryDao: LearningStatsSummaryDao,
    private val vocabularyRepository: VocabularyRepository
) {
    fun observeStats(): Flow<DailyStats?> =
        learningStatsSummaryDao.observe().map { it?.toModel() }

    suspend fun getStats(): DailyStats? =
        learningStatsSummaryDao.get()?.toModel()

    /**
     * Record reading activity for today.
     */
    suspend fun recordReadingActivity(secondsSpent: Int = 0) {
        val today = ContextaTypeConverters.currentDateString()
        // Ensure row exists before updating
        val existing = dailyLearningLogDao.getByDate(today)
        if (existing == null) {
            dailyLearningLogDao.upsert(
                com.ak.contexta.data.local.entity.DailyLearningLogEntity(
                    logDate = today,
                    articlesRead = 1,
                    secondsSpent = secondsSpent
                )
            )
        } else {
            dailyLearningLogDao.addActivity(today, 1, secondsSpent)
        }
        recalculateStats(today)
    }

    /**
     * Record adding a word to vocabulary.
     */
    suspend fun recordWordAdded() {
        val today = ContextaTypeConverters.currentDateString()
        // Ensure row exists
        val existing = dailyLearningLogDao.getByDate(today)
        if (existing == null) {
            dailyLearningLogDao.upsert(
                com.ak.contexta.data.local.entity.DailyLearningLogEntity(
                    logDate = today,
                    wordsAdded = 1
                )
            )
        } else {
            dailyLearningLogDao.addWordActivity(today)
        }
        recalculateStats(today)
    }

    /**
     * Recalculate learning_stats_summary from daily_learning_log data.
     */
    private suspend fun recalculateStats(today: String) {
        val activeDates = dailyLearningLogDao.getActiveDates()
        val currentStreak = calculateStreak(activeDates, today)
        val totalDays = activeDates.size

        val existing = learningStatsSummaryDao.get()
        val newLongestStreak = maxOf(existing?.longestStreak ?: 0, currentStreak)
        val totalWords = vocabularyRepository.countDistinctWords()

        // Sum articles_read and words_added from the daily log
        val totalArticlesRead = activeDates.sumOf { date ->
            dailyLearningLogDao.getByDate(date)?.articlesRead ?: 0
        }

        learningStatsSummaryDao.upsert(
            LearningStatsSummaryEntity(
                id = 1,
                totalArticlesRead = totalArticlesRead,
                totalWordsAdded = totalWords,
                totalWordsMastered = 0, // TODO: compute from vocabulary_entries
                totalLearningDays = totalDays,
                currentStreak = currentStreak,
                longestStreak = newLongestStreak,
                lastActiveDate = today
            )
        )
    }

    /**
     * Calculate the current streak (consecutive active days ending at today).
     */
    private fun calculateStreak(activeDates: List<String>, today: String): Int {
        if (activeDates.isEmpty()) return 0

        val zoneId = ZoneId.of("Asia/Shanghai")
        val todayDate = LocalDate.parse(today)

        // Check if today has activity; if not, the streak might start from yesterday
        val lastActive = LocalDate.parse(activeDates.first())
        val diff = ChronoUnit.DAYS.between(lastActive, todayDate)

        if (diff > 1) return 0 // broken streak
        if (diff == 0L) {
            // Today is active — count backwards
            var streak = 1
            var checkDate = todayDate.minusDays(1)
            while (activeDates.contains(checkDate.toString())) {
                streak++
                checkDate = checkDate.minusDays(1)
            }
            return streak
        }
        // diff == 1, last active was yesterday
        var streak = 1
        var checkDate = lastActive.minusDays(1)
        while (activeDates.contains(checkDate.toString())) {
            streak++
            checkDate = checkDate.minusDays(1)
        }
        return streak
    }

    private fun LearningStatsSummaryEntity.toModel() = DailyStats(
        totalArticlesRead = totalArticlesRead,
        totalWordsAdded = totalWordsAdded,
        totalWordsMastered = totalWordsMastered,
        totalLearningDays = totalLearningDays,
        currentStreak = currentStreak,
        longestStreak = longestStreak,
        lastActiveDate = lastActiveDate
    )
}
