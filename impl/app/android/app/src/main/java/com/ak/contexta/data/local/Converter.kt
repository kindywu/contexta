package com.ak.contexta.data.local

import androidx.room.TypeConverter
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class ContextaTypeConverters {

    @TypeConverter
    fun fromTimestamp(value: Long?): Long? = value

    @TypeConverter
    fun toTimestamp(value: Long?): Long? = value

    @TypeConverter
    fun fromDateString(value: String?): String? = value

    @TypeConverter
    fun toDateString(value: String?): String? = value

    companion object {
        private val dateFormatter = DateTimeFormatter.ISO_LOCAL_DATE
        private val zoneId = ZoneId.of("Asia/Shanghai")

        fun currentDateString(): String {
            return LocalDate.now(zoneId).format(dateFormatter)
        }

        fun timestampToDateString(timestamp: Long): String {
            return Instant.ofEpochMilli(timestamp)
                .atZone(zoneId)
                .toLocalDate()
                .format(dateFormatter)
        }

        fun isToday(timestamp: Long): Boolean {
            val date = timestampToDateString(timestamp)
            return date == currentDateString()
        }

        fun isSameMonth(timestamp: Long, dateString: String): Boolean {
            val month1 = timestampToDateString(timestamp).take(7) // "2026-07"
            val month2 = dateString.take(7)
            return month1 == month2
        }
    }
}
