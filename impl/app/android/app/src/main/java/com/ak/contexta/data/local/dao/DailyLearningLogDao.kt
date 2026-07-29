package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.DailyLearningLogEntity

@Dao
interface DailyLearningLogDao {
    @Query("SELECT * FROM daily_learning_log WHERE log_date = :date")
    suspend fun getByDate(date: String): DailyLearningLogEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(log: DailyLearningLogEntity)

    @Query("""
        UPDATE daily_learning_log
        SET articles_read = articles_read + :articlesDelta,
            seconds_spent = seconds_spent + :secondsDelta
        WHERE log_date = :date
    """)
    suspend fun addActivity(date: String, articlesDelta: Int, secondsDelta: Int)

    @Query("""
        UPDATE daily_learning_log
        SET words_added = words_added + 1
        WHERE log_date = :date
    """)
    suspend fun addWordActivity(date: String)

    @Query("SELECT COUNT(*) FROM daily_learning_log WHERE seconds_spent > 0 OR articles_read > 0 OR words_added > 0")
    suspend fun countActiveDays(): Int

    @Query("SELECT DISTINCT log_date FROM daily_learning_log WHERE seconds_spent > 0 OR articles_read > 0 OR words_added > 0 ORDER BY log_date DESC")
    suspend fun getActiveDates(): List<String>
}
