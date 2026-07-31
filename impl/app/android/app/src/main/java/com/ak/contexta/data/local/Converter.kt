package com.ak.contexta.data.local

import androidx.room.TypeConverter
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
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
        private val dateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX")

        /**
         * 手机当前时区。所有落库时间字段统一使用手机时区，不硬编码。
         */
        val zoneId: ZoneId
            get() = ZoneId.systemDefault()

        fun currentDateString(): String {
            return LocalDate.now(zoneId).format(dateFormatter)
        }

        /**
         * 当前时间字符串（ISO 8601 秒级带时区偏移，如 "2026-07-31T10:30:00+08:00"）。
         * 用于所有落库时间字段，替代 Unix 毫秒时间戳。
         */
        fun currentDateTimeString(): String {
            // 必须转 ZonedDateTime 才能格式化 XXX（OffsetSeconds）字段
            return LocalDateTime.now(zoneId).atZone(zoneId).format(dateTimeFormatter)
        }

        /**
         * 将固定年月日时分转换为带手机时区的 ISO 日期时间字符串（如种子数据的完成时间）。
         */
        fun dateTimeStringAt(year: Int, month: Int, day: Int, hour: Int, minute: Int): String {
            return LocalDateTime.of(year, month, day, hour, minute)
                .atZone(zoneId)
                .format(dateTimeFormatter)
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
