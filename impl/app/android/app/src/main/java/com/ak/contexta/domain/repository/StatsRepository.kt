package com.ak.contexta.domain.repository

import com.ak.contexta.domain.model.DailyStats
import kotlinx.coroutines.flow.Flow

interface StatsRepository {
    fun observeStats(): Flow<DailyStats?>

    suspend fun getStats(): DailyStats?

    /** Record reading activity for today. */
    suspend fun recordReadingActivity(secondsSpent: Int = 0)

    /** Record adding a word to vocabulary. */
    suspend fun recordWordAdded()
}
