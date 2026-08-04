package com.ak.contexta.data.remote

import com.ak.contexta.BuildConfig
import com.ak.contexta.domain.error.LlmRecoverableExhaustedException
import com.ak.contexta.domain.error.LlmTimeoutException
import io.mockk.coEvery
import io.mockk.mockk
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * 验证 LlmCaller 的超时路径：withTimeoutOrNull 超时后必须走到
 * throw LlmTimeoutException（而非被 catch(Exception) 吞掉后误分类）。
 */
class LlmCallerTest {

    private val api: DeepSeekApi = mockk()
    private val caller = LlmCaller(api)

    @Test
    fun `网络调用挂起超时后抛 LlmTimeoutException`() = runTest {
        // 模拟网络挂起（MIUI 后台节流）：挂起远超过时预算
        coEvery { api.chatCompletion(any()) } coAnswers {
            delay(10_000)
            throw IllegalStateException("unreachable")
        }

        // 关键验证点：TimeoutCancellationException 会被 LlmCaller 的 catch(Exception)
        // 捕获并分类为 Recoverable，随后 delay 在已取消协程中抛 CancellationException，
        // withTimeoutOrNull 应将其转换为 null → 走到 throw LlmTimeoutException
        try {
            caller.call("s", "u", 500)
            fail("expected LlmTimeoutException")
        } catch (e: LlmTimeoutException) {
            // 预期
        }
    }

    @Test
    fun `超时发生在最后一次尝试时 仍按 LLM_TIMEOUT 分类`() = runTest {
        // 前 MAX_RETRIES 次尝试：HTTP 500（可恢复，触发退避重试）
        // 最后一次尝试：挂起远超剩余预算，等待总预算（20s）超时
        val attempts = AtomicInteger(0)
        coEvery { api.chatCompletion(any()) } coAnswers {
            if (attempts.incrementAndGet() <= BuildConfig.LLM_MAX_RETRIES) {
                throw IOException("HTTP 500 Server Error")
            }
            delay(60_000)
            throw IllegalStateException("unreachable")
        }

        // catch 顶部的 CancellationException 防护使超时确定性分类为 LLM_TIMEOUT，
        // 不再经过 retryCount++ > MAX_RETRIES 检查被误报为 RecoverableExhausted
        try {
            caller.call("s", "u", 20_000)
            fail("expected LlmTimeoutException")
        } catch (e: LlmTimeoutException) {
            // 预期
        }
    }

    @Test
    fun `真正的外部取消传播 CancellationException 而非误分类`() = runTest {
        // 前 MAX_RETRIES 次尝试失败后，最后一次尝试挂起（等待被取消）
        val lastAttemptStarted = CompletableDeferred<Unit>()
        val attempts = AtomicInteger(0)
        coEvery { api.chatCompletion(any()) } coAnswers {
            if (attempts.incrementAndGet() <= BuildConfig.LLM_MAX_RETRIES) {
                throw IOException("HTTP 500 Server Error")
            }
            lastAttemptStarted.complete(Unit)
            delay(10_000)
            throw IllegalStateException("unreachable")
        }

        val job = launch {
            caller.call("s", "u", 20_000)
        }
        lastAttemptStarted.await() // 最后一次尝试已挂起，此时取消
        job.cancel()
        job.join()

        // 修复后：取消传播为 CancellationException，job 以取消结束
        // 修复前：CancellationException 被 catch(Exception) 吞掉 → retryCount++ > MAX →
        //         抛 LlmRecoverableExhaustedException，job 以异常完成（isCancelled = false）
        assertTrue(job.isCancelled)
    }
}
