package com.ak.contexta.data.time

import com.ak.contexta.domain.time.TimeProvider
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

/**
 * [TimeProvider] 的生产实现，基于系统时钟。
 * 所有 Repository / Use Case 通过此接口获取时间，替代直接调用 System.currentTimeMillis()。
 */
@Singleton
class SystemTimeProvider @Inject constructor() : TimeProvider {
    override fun nowMillis(): Long = System.currentTimeMillis()

    override fun todayDateString(): String =
        LocalDate.now(ZoneId.of("Asia/Shanghai")).toString()
}
