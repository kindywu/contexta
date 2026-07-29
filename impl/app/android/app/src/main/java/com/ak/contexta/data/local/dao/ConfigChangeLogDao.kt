package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.ak.contexta.data.local.entity.ConfigChangeLogEntity

@Dao
interface ConfigChangeLogDao {
    @Insert
    suspend fun insert(log: ConfigChangeLogEntity)

    @Query("SELECT COUNT(*) FROM config_change_log WHERE field_name = :fieldName AND created_at >= :dayStartMillis AND created_at < :dayEndMillis")
    suspend fun countToday(fieldName: String, dayStartMillis: Long, dayEndMillis: Long): Int

    @Query("SELECT COUNT(*) FROM config_change_log WHERE field_name = :fieldName AND created_at >= :monthStartMillis AND created_at < :monthEndMillis")
    suspend fun countThisMonth(fieldName: String, monthStartMillis: Long, monthEndMillis: Long): Int
}
