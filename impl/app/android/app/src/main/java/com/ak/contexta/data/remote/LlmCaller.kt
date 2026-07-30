package com.ak.contexta.data.remote

import com.ak.contexta.BuildConfig
import com.ak.contexta.data.remote.dto.ChatCompletionRequest
import com.ak.contexta.data.remote.dto.ChatMessage
import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.LlmErrorClassifier
import com.ak.contexta.domain.error.LlmFatalException
import com.ak.contexta.domain.error.LlmRecoverableExhaustedException
import com.ak.contexta.domain.error.PipelineBlockingException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Unified LLM caller with retry logic.
 * - Recoverable errors (network, 429, 5xx, bad JSON): retry up to 3 times
 * - Non-recoverable errors (401, 403, 400): throw immediately
 * - Structural errors (DB, serialization): throw PipelineBlockingException
 */
@Singleton
class LlmCaller @Inject constructor(
    private val deepSeekApi: DeepSeekApi
) : LlmClient {

    companion object {
        private const val MAX_RETRIES = 3
        private const val GENERATION_TIMEOUT_MS = 120_000L // 2 minutes
        private const val MAX_RETRY_AFTER_SECONDS = 30
    }

    /**
     * Call LLM with the given system and user prompts.
     * Returns the response content or throws.
     */
    override suspend fun call(
        systemPrompt: String,
        userPrompt: String,
        timeoutMs: Long
    ): LlmClient.LlmResult = withTimeout(timeoutMs) {
        var retryCount = 0
        var lastError: Throwable? = null

        while (retryCount <= MAX_RETRIES) {
            try {
                val request = ChatCompletionRequest(
                    model = BuildConfig.DEEPSEEK_MODEL,
                    messages = listOf(
                        ChatMessage(role = "system", content = systemPrompt),
                        ChatMessage(role = "user", content = userPrompt)
                    )
                )

                val response = deepSeekApi.chatCompletion(request)
                val content = response.choices.firstOrNull()?.message?.content
                    ?: throw IllegalStateException("Empty response from LLM")

                return@withTimeout LlmClient.LlmResult(content = content, retryCount = retryCount)

            } catch (e: Exception) {
                lastError = e

                // Classify the error
                val httpCode = extractHttpCode(e)
                when (val classified = LlmErrorClassifier.classify(httpCode, e)) {
                    // Structural: immediately block the pipeline
                    is LlmErrorClassifier.LlmError.Structural -> {
                        throw PipelineBlockingException(
                            "Structural error: ${classified.cause.message}",
                            classified.cause
                        )
                    }
                    // LLM Fatal: fail the task (user can retry)
                    is LlmErrorClassifier.LlmError.LlmFatal -> {
                        throw LlmFatalException(
                            "Non-recoverable LLM error: ${classified.cause.message}",
                            classified.cause
                        )
                    }
                    // Recoverable: retry with backoff
                    is LlmErrorClassifier.LlmError.Recoverable -> {
                        retryCount++
                        if (retryCount > MAX_RETRIES) {
                            throw LlmRecoverableExhaustedException(
                                "LLM call failed after $MAX_RETRIES retries: ${classified.cause.message}",
                                classified.cause,
                                retryCount - 1 // actual attempts
                            )
                        }
                        // Wait: Retry-After if 429, else exponential backoff
                        val waitMs = if (classified.retryAfterSeconds != null) {
                            (classified.retryAfterSeconds.coerceAtMost(MAX_RETRY_AFTER_SECONDS) * 1000L)
                        } else {
                            (2000L * Math.pow(2.0, (retryCount - 1).toDouble())).toLong()
                                .coerceAtMost(10_000)
                        }
                        delay(waitMs)
                    }
                }
            }
        }

        // Should not reach here
        throw LlmRecoverableExhaustedException(
            "LLM call failed after $MAX_RETRIES retries",
            lastError,
            MAX_RETRIES
        )
    }

    private fun extractHttpCode(e: Exception): Int? {
        // Try to extract HTTP status from Retrofit/OkHttp exceptions
        val message = e.message ?: return null
        val match = Regex("HTTP (\\d+)").find(message)
        return match?.groupValues?.get(1)?.toIntOrNull()
    }
}
