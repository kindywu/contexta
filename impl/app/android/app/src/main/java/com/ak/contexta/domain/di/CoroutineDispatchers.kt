package com.ak.contexta.domain.di

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * CoroutineDispatcher 注入容器。
 * 在测试中替换为 [kotlinx.coroutines.test.UnconfinedTestDispatcher]，
 * 使所有协程同步执行，无需 delay。
 */
data class CoroutineDispatchers(
    val main: CoroutineDispatcher = Dispatchers.Main,
    val io: CoroutineDispatcher = Dispatchers.IO,
    val default: CoroutineDispatcher = Dispatchers.Default
)
