package com.ak.contexta.domain.time

/**
 * 时间抽象接口，替换所有直接的 [System.currentTimeMillis] 调用。
 * 在测试中通过 [FakeTimeProvider] 固定时间，确保可重复性。
 */
interface TimeProvider {
    /** 当前 Unix 毫秒时间戳（仅用于内存计算，如 Feishu 去重窗口、签名） */
    fun nowMillis(): Long

    /**
     * 当前日期时间字符串（手机时区，ISO 8601 秒级带 offset，如 "2026-07-31T10:30:00+08:00"）。
     * 用于所有落库时间字段。
     */
    fun nowDateTimeString(): String

    /** 当前日期字符串（手机时区，ISO 格式 yyyy-MM-dd） */
    fun todayDateString(): String
}
