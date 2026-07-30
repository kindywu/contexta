package com.ak.contexta.domain.error

import com.ak.contexta.domain.LlmErrorClassifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for [LlmErrorClassifier.classify] — verifies error classification logic.
 */
class LlmErrorClassifierTest {

    // ─── Recoverable ───

    @Test
    fun `null http code is recoverable`() {
        val result = LlmErrorClassifier.classify(null, RuntimeException("Network timeout"))
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }

    @Test
    fun `http 429 is recoverable with retry-after`() {
        val result = LlmErrorClassifier.classify(429, RuntimeException("Retry-After: 30"))
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
        val r = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(30, r.retryAfterSeconds)
    }

    @Test
    fun `http 500-599 is recoverable`() {
        val result = LlmErrorClassifier.classify(500, RuntimeException("Internal error"))
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)

        val r503 = LlmErrorClassifier.classify(503, RuntimeException("Service unavailable"))
        assertTrue(r503 is LlmErrorClassifier.LlmError.Recoverable)
    }

    @Test
    fun `JSON parse error is recoverable`() {
        val result = LlmErrorClassifier.classify(200, RuntimeException("JSON parse error"))
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }

    // ─── LlmFatal ───

    @Test
    fun `http 401 is llm fatal`() {
        val result = LlmErrorClassifier.classify(401, RuntimeException("Unauthorized"))
        assertTrue(result is LlmErrorClassifier.LlmError.LlmFatal)
    }

    @Test
    fun `http 403 is llm fatal`() {
        val result = LlmErrorClassifier.classify(403, RuntimeException("Forbidden"))
        assertTrue(result is LlmErrorClassifier.LlmError.LlmFatal)
    }

    @Test
    fun `http 400 is llm fatal`() {
        val result = LlmErrorClassifier.classify(400, RuntimeException("Bad request"))
        assertTrue(result is LlmErrorClassifier.LlmError.LlmFatal)
    }

    // ─── Structural ───

    @Test
    fun `pipeline blocking exception is structural`() {
        val result = LlmErrorClassifier.classify(
            null, PipelineBlockingException("DB constraint violation")
        )
        assertTrue(result is LlmErrorClassifier.LlmError.Structural)
    }

    @Test
    fun `constraint violation message is structural`() {
        val result = LlmErrorClassifier.classify(
            null, RuntimeException("Constraint violation: unique index")
        )
        assertTrue(result is LlmErrorClassifier.LlmError.Structural)
    }

    @Test
    fun `disk IO error message is structural`() {
        val result = LlmErrorClassifier.classify(
            null, RuntimeException("disk I/O error during write")
        )
        assertTrue(result is LlmErrorClassifier.LlmError.Structural)
    }

    // ─── Edge cases ───

    @Test
    fun `unknown http code defaults to recoverable`() {
        val result = LlmErrorClassifier.classify(418, RuntimeException("Teapot"))
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }
}
