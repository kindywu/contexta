package com.ak.contexta.domain.time

/**
 * 时间抽象接口，替换所有直接的 [System.currentTimeMillis] 调用。
 * 在测试中通过 [FakeTimeProvider] 固定时间，确保可重复性。
 */
interface TimeProvider {
    /** 当前 Unix 毫秒时间戳 */
    fun nowMillis(): Long

    /** 当前日期字符串（Asia/Shanghai 时区，ISO 格式 yyyy-MM-dd） */
    fun todayDateString(): String
}
