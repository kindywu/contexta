package com.ak.contexta.domain

import com.ak.contexta.domain.error.PipelineBlockingException

/**
 * Classifies LLM call errors into three categories:
 * - Recoverable: network issues, 429 rate-limit, 5xx, bad JSON → retryable
 * - LlmFatal: 401/403 auth, 400 bad request, content policy → fail immediately, user can retry
 * - Structural: DB constraint violations, serialization errors → BLOCKED state
 */
object LlmErrorClassifier {

    sealed class LlmError {
        /** Recoverable — retry with backoff */
        data class Recoverable(val cause: Throwable, val retryAfterSeconds: Int? = null) : LlmError()
        /** Non-recoverable LLM-side error — fail the task, user can retry */
        data class LlmFatal(val cause: Throwable) : LlmError()
        /** Structural code-level error — block the pipeline, needs app fix */
        data class Structural(val cause: Throwable) : LlmError()
    }

    fun classify(httpCode: Int?, throwable: Throwable): LlmError {
        // Structural errors first — these are local, not LLM responses
        when {
            throwable is PipelineBlockingException -> return LlmError.Structural(throwable)
            throwable.message?.contains("Constraint") == true ->
                return LlmError.Structural(throwable)
            throwable.message?.contains("disk I/O") == true ->
                return LlmError.Structural(throwable)
        }

        val code = httpCode
        return when {
            // Recoverable
            code == null -> LlmError.Recoverable(throwable) // network error
            code == 429 -> {
                val retryAfter = extractRetryAfter(throwable.message)
                LlmError.Recoverable(throwable, retryAfter)
            }
            code in 500..599 -> LlmError.Recoverable(throwable)
            throwable.message?.contains("JSON") == true ||
                throwable.message?.contains("parse") == true ||
                throwable.message?.contains("syntax") == true -> LlmError.Recoverable(throwable)

            // LLM Fatal
            code == 400 -> LlmError.LlmFatal(throwable)
            code == 401 || code == 403 -> LlmError.LlmFatal(throwable)

            // Everything else
            else -> LlmError.Recoverable(throwable)
        }
    }

    private fun extractRetryAfter(message: String?): Int? {
        if (message == null) return null
        val match = Regex("Retry-After[=:\\s]+(\\d+)").find(message)
        return match?.groupValues?.get(1)?.toIntOrNull()
    }
}
