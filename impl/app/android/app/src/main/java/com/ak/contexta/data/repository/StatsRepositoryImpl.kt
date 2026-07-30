package com.ak.contexta.data.repository

import com.ak.contexta.data.local.ContextaTypeConverters
import com.ak.contexta.data.local.dao.DailyLearningLogDao
import com.ak.contexta.data.local.dao.LearningStatsSummaryDao
import com.ak.contexta.data.local.entity.DailyLearningLogEntity
import com.ak.contexta.data.local.entity.LearningStatsSummaryEntity
import com.ak.contexta.domain.model.DailyStats
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StatsRepositoryImpl @Inject constructor(
    private val dailyLearningLogDao: DailyLearningLogDao,
    private val learningStatsSummaryDao: LearningStatsSummaryDao,
    private val vocabularyRepository: VocabularyRepository
) : StatsRepository {

    override fun observeStats(): Flow<DailyStats?> =
        learningStatsSummaryDao.observe().map { it?.toModel() }

    override suspend fun getStats(): DailyStats? =
        learningStatsSummaryDao.get()?.toModel()

    override suspend fun recordReadingActivity(secondsSpent: Int) {
        val today = ContextaTypeConverters.currentDateString()
        val existing = dailyLearningLogDao.getByDate(today)
        if (existing == null) {
            dailyLearningLogDao.upsert(
                DailyLearningLogEntity(
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

    override suspend fun recordWordAdded() {
        val today = ContextaTypeConverters.currentDateString()
        val existing = dailyLearningLogDao.getByDate(today)
        if (existing == null) {
            dailyLearningLogDao.upsert(
                DailyLearningLogEntity(
                    logDate = today,
                    wordsAdded = 1
                )
            )
        } else {
            dailyLearningLogDao.addWordActivity(today)
        }
        recalculateStats(today)
    }

    private suspend fun recalculateStats(today: String) {
        val activeDates = dailyLearningLogDao.getActiveDates()
        val currentStreak = calculateStreak(activeDates, today)
        val totalDays = activeDates.size

        val existing = learningStatsSummaryDao.get()
        val newLongestStreak = maxOf(existing?.longestStreak ?: 0, currentStreak)
        val totalWords = vocabularyRepository.countDistinctWords()

        val totalArticlesRead = activeDates.sumOf { date ->
            dailyLearningLogDao.getByDate(date)?.articlesRead ?: 0
        }

        learningStatsSummaryDao.upsert(
            LearningStatsSummaryEntity(
                id = 1,
                totalArticlesRead = totalArticlesRead,
                totalWordsAdded = totalWords,
                totalWordsMastered = 0,
                totalLearningDays = totalDays,
                currentStreak = currentStreak,
                longestStreak = newLongestStreak,
                lastActiveDate = today
            )
        )
    }

    private fun calculateStreak(activeDates: List<String>, today: String): Int {
        if (activeDates.isEmpty()) return 0

        val zoneId = ZoneId.of("Asia/Shanghai")
        val todayDate = LocalDate.parse(today)

        val lastActive = LocalDate.parse(activeDates.first())
        val diff = ChronoUnit.DAYS.between(lastActive, todayDate)

        if (diff > 1) return 0
        if (diff == 0L) {
            var streak = 1
            var checkDate = todayDate.minusDays(1)
            while (activeDates.contains(checkDate.toString())) {
                streak++
                checkDate = checkDate.minusDays(1)
            }
            return streak
        }
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
