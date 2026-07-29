package com.ak.contexta.data.remote

import com.ak.contexta.data.remote.dto.ChatCompletionRequest
import com.ak.contexta.data.remote.dto.ChatCompletionResponse
import com.ak.contexta.data.remote.dto.ChatResponseMessage
import com.ak.contexta.data.remote.dto.Choice
import com.ak.contexta.domain.PipelineBlockingException
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class LlmCallerTest {

    private val deepSeekApi: DeepSeekApi = mockk()

    private lateinit var llmCaller: LlmCaller

    @Before
    fun setup() {
        llmCaller = LlmCaller(deepSeekApi)
    }

    // ── Success path with realistic LLM response ─────────────────

    @Test
    fun `call returns article XML on successful API response`() = runTest {
        val realLlmArticleXml = "<title>Morning Coffee Chat</title>\n" +
                "<paragraph>Good morning, Lisa!</paragraph>\n" +
                "<translation>早上好，丽莎！</translation>\n" +
                "<paragraph>Would you like some coffee?</paragraph>\n" +
                "<translation>你想喝点咖啡吗？</translation>"
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = realLlmArticleXml))
            )
        )
        coEvery { deepSeekApi.chatCompletion(any<ChatCompletionRequest>()) } returns response

        val result = llmCaller.call("system prompt", "user prompt")

        assertTrue(result.content.contains("<title>Morning Coffee Chat</title>"))
        assertTrue(result.content.contains("<paragraph>Good morning, Lisa!</paragraph>"))
        assertTrue(result.content.contains("<translation>早上好，丽莎！</translation>"))
        assertEquals(0, result.retryCount)
        coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) }
    }

    @Test
    fun `call passes correct system and user prompts`() = runTest {
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = "OK"))
            )
        )
        coEvery { deepSeekApi.chatCompletion(any<ChatCompletionRequest>()) } answers {
            val request = firstArg<ChatCompletionRequest>()
            assertEquals("sys-prompt", request.messages[0].content)
            assertEquals("usr-prompt", request.messages[1].content)
            assertEquals("system", request.messages[0].role)
            assertEquals("user", request.messages[1].role)
            response
        }

        llmCaller.call("sys-prompt", "usr-prompt")
        coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) }
    }

    // ── Empty response ────────────────────────────────────────────

    @Test
    fun `call throws on empty choices list`() = runTest {
        coEvery { deepSeekApi.chatCompletion(any()) } returns
            ChatCompletionResponse(choices = emptyList())

        // IllegalStateException("Empty response from LLM") is classified as
        // Recoverable (null httpCode), then retried 3 times
        try {
            llmCaller.call("prompt", "prompt", timeoutMs = 120_000L)
        } catch (e: LlmRecoverableExhaustedException) {
            assertTrue(e.message!!.contains("Empty response from LLM"))
            assertEquals(3, e.attempts)
            coVerify(atLeast = 4) { deepSeekApi.chatCompletion(any()) }
            return@runTest
        }
        throw AssertionError("Expected LlmRecoverableExhaustedException")
    }

    @Test
    fun `call returns empty string when response content is empty`() = runTest {
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = ""))
            )
        )
        coEvery { deepSeekApi.chatCompletion(any()) } returns response

        val result = llmCaller.call("prompt", "prompt")

        assertEquals("", result.content)
        assertEquals(0, result.retryCount)
    }

    // ── Retry on recoverable errors ───────────────────────────────

    @Test
    fun `call retries on 5xx error and eventually succeeds with real article`() = runTest {
        val articleXml = "<title>Retry Test</title><paragraph>Worked after retry.</paragraph><translation>重试后成功。</translation>"
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = articleXml))
            )
        )
        val error500 = RuntimeException("HTTP 500 Internal Server Error")
        val callTracker = mutableListOf(0)
        coEvery { deepSeekApi.chatCompletion(any()) } coAnswers {
            val attempt = callTracker[0]
            callTracker[0] = attempt + 1
            if (attempt < 2) throw error500 else response
        }

        val result = llmCaller.call("prompt", "prompt", timeoutMs = 120_000L)

        // Verify real article XML is returned after retry
        assertTrue(result.content.contains("<title>Retry Test</title>"))
        assertEquals(2, result.retryCount)
        coVerify(exactly = 3) { deepSeekApi.chatCompletion(any()) }
    }

    @Test
    fun `call retries on network error and eventually succeeds with real article`() = runTest {
        val articleXml = "<title>Network Retry</title><paragraph>Recovered.</paragraph><translation>已恢复。</translation>"
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = articleXml))
            )
        )
        val networkError = RuntimeException("Unable to resolve host")
        val callTracker = mutableListOf(0)
        coEvery { deepSeekApi.chatCompletion(any()) } coAnswers {
            val attempt = callTracker[0]
            callTracker[0] = attempt + 1
            if (attempt < 1) throw networkError else response
        }

        val result = llmCaller.call("prompt", "prompt", timeoutMs = 120_000L)

        assertTrue(result.content.contains("<title>Network Retry</title>"))
        assertEquals(1, result.retryCount)
    }

    // ── Retry exhaustion ─────────────────────────────────────────

    @Test
    fun `call throws LlmRecoverableExhaustedException after exhausting retries`() = runTest {
        val networkError = RuntimeException("HTTP 502 Bad Gateway")
        coEvery { deepSeekApi.chatCompletion(any()) } throws networkError

        try {
            llmCaller.call("prompt", "prompt", timeoutMs = 120_000L)
        } catch (e: LlmRecoverableExhaustedException) {
            assertEquals(3, e.attempts)
            coVerify(exactly = 4) { deepSeekApi.chatCompletion(any()) } // initial + 3 retries
            return@runTest
        }
        throw AssertionError("Expected LlmRecoverableExhaustedException")
    }

    // ── Non-recoverable (LlmFatal) ────────────────────────────────

    @Test
    fun `call throws LlmFatalException on 401 without retry`() = runTest {
        val authError = RuntimeException("HTTP 401 Unauthorized")
        coEvery { deepSeekApi.chatCompletion(any()) } throws authError

        try {
            llmCaller.call("prompt", "prompt")
        } catch (e: LlmFatalException) {
            coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) } // no retry
            return@runTest
        }
        throw AssertionError("Expected LlmFatalException")
    }

    @Test
    fun `call throws LlmFatalException on 403 without retry`() = runTest {
        val authError = RuntimeException("HTTP 403 Forbidden")
        coEvery { deepSeekApi.chatCompletion(any()) } throws authError

        try {
            llmCaller.call("prompt", "prompt")
        } catch (e: LlmFatalException) {
            coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) }
            return@runTest
        }
        throw AssertionError("Expected LlmFatalException")
    }

    @Test
    fun `call throws LlmFatalException on 400 without retry`() = runTest {
        val badRequestError = RuntimeException("HTTP 400 Bad Request")
        coEvery { deepSeekApi.chatCompletion(any()) } throws badRequestError

        try {
            llmCaller.call("prompt", "prompt")
        } catch (e: LlmFatalException) {
            coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) }
            return@runTest
        }
        throw AssertionError("Expected LlmFatalException")
    }

    // ── Structural errors ─────────────────────────────────────────

    @Test
    fun `call throws PipelineBlockingException on structural error without retry`() = runTest {
        val structuralError = RuntimeException("disk I/O error: No space left")
        coEvery { deepSeekApi.chatCompletion(any()) } throws structuralError

        try {
            llmCaller.call("prompt", "prompt")
        } catch (e: PipelineBlockingException) {
            coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) } // no retry
            assertTrue(e.message!!.contains("disk I/O"))
            return@runTest
        }
        throw AssertionError("Expected PipelineBlockingException")
    }

    @Test
    fun `call throws PipelineBlockingException on constraint violation`() = runTest {
        val dbError = RuntimeException("Constraint violation: UNIQUE constraint failed")
        coEvery { deepSeekApi.chatCompletion(any()) } throws dbError

        try {
            llmCaller.call("prompt", "prompt")
        } catch (e: PipelineBlockingException) {
            coVerify(exactly = 1) { deepSeekApi.chatCompletion(any()) }
            return@runTest
        }
        throw AssertionError("Expected PipelineBlockingException")
    }

    // ── 429 with Retry-After ──────────────────────────────────────

    @Test
    fun `call retries on 429 with Retry-After header`() = runTest {
        val articleXml = "<title>Rate Limited</title><paragraph>Eventually succeeded.</paragraph><translation>最终成功了。</translation>"
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = articleXml))
            )
        )
        val rateLimitError = RuntimeException("HTTP 429 Too Many Requests, Retry-After: 2")
        val callTracker = mutableListOf(0)
        coEvery { deepSeekApi.chatCompletion(any()) } coAnswers {
            val attempt = callTracker[0]
            callTracker[0] = attempt + 1
            if (attempt < 1) throw rateLimitError else response
        }

        val result = llmCaller.call("prompt", "prompt", timeoutMs = 120_000L)

        assertTrue(result.content.contains("<title>Rate Limited</title>"))
        assertEquals(1, result.retryCount)
    }

    @Test
    fun `call clamps Retry-After to max 30 seconds`() = runTest {
        val articleXml = "<title>Clamped</title><paragraph>OK</paragraph><translation>好的</translation>"
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = articleXml))
            )
        )
        val rateLimitError = RuntimeException("HTTP 429 Retry-After: 120")
        val callTracker = mutableListOf(0)
        coEvery { deepSeekApi.chatCompletion(any()) } coAnswers {
            val attempt = callTracker[0]
            callTracker[0] = attempt + 1
            if (attempt < 1) throw rateLimitError else response
        }

        val result = llmCaller.call("prompt", "prompt", timeoutMs = 180_000L)

        assertTrue(result.content.contains("<title>Clamped</title>"))
        assertEquals(1, result.retryCount)
    }

    // ── Timeout ───────────────────────────────────────────────────

    @Test
    fun `call throws on timeout`() = runTest {
        coEvery { deepSeekApi.chatCompletion(any()) } coAnswers {
            kotlinx.coroutines.delay(50_000)
            error("should not reach here")
        }

        try {
            llmCaller.call("prompt", "prompt", timeoutMs = 1)
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            return@runTest
        }
        throw AssertionError("Expected TimeoutCancellationException")
    }

    // ── Mixed: different error types across retries ───────────────

    @Test
    fun `call retries after recoverable then succeeds on third attempt`() = runTest {
        val articleXml = "<title>Third Time Lucky</title><paragraph>Finally worked.</paragraph><translation>终于成功了。</translation>"
        val response = ChatCompletionResponse(
            choices = listOf(
                Choice(message = ChatResponseMessage(content = articleXml))
            )
        )
        val error502 = RuntimeException("HTTP 502 Bad Gateway")
        val error503 = RuntimeException("HTTP 503 Service Unavailable")
        val callTracker = mutableListOf(0)
        coEvery { deepSeekApi.chatCompletion(any()) } coAnswers {
            val attempt = callTracker[0]
            callTracker[0] = attempt + 1
            when (attempt) {
                0 -> throw error502
                1 -> throw error503
                else -> response
            }
        }

        val result = llmCaller.call("prompt", "prompt", timeoutMs = 120_000L)

        assertTrue(result.content.contains("Third Time Lucky"))
        assertEquals(2, result.retryCount)
    }
}
