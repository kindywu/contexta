package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.DailyLearningEntity

@Dao
interface DailyLearningDao {
    /** 获取所有学习记录（按日期降序）。 */
    @Query("SELECT * FROM daily_learning ORDER BY learning_date DESC")
    suspend fun getAll(): List<DailyLearningEntity>

    /** 获取最新一条学习记录。 */
    @Query("SELECT * FROM daily_learning ORDER BY learning_date DESC LIMIT 1")
    suspend fun getLatest(): DailyLearningEntity?

    /** 获取指定日期的学习记录。 */
    @Query("SELECT * FROM daily_learning WHERE learning_date = :learningDate")
    suspend fun getByLearningDate(learningDate: String): DailyLearningEntity?

    /** 获取所有 daily_learning 中最大 ref_batch_date。为 null 表示尚无学习记录。 */
    @Query("SELECT MAX(ref_batch_date) FROM daily_learning")
    suspend fun getMaxRefBatchDate(): String?

    /** 插入学习记录。[learningDate] 为 PRIMARY KEY，重复会冲突。 */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(record: DailyLearningEntity)
}
