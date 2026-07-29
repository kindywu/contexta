package com.ak.contexta.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LlmErrorClassifierTest {

    // ── Recoverable ────────────────────────────────────────────────

    @Test
    fun `network error with null httpCode returns Recoverable`() {
        val error = RuntimeException("Connection refused")
        val result = LlmErrorClassifier.classify(null, error)

        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(error, recoverable.cause)
        assertEquals(null, recoverable.retryAfterSeconds)
    }

    @Test
    fun `http 429 returns Recoverable with retryAfterSeconds`() {
        val error = RuntimeException("HTTP 429 Too Many Requests, Retry-After: 15")
        val result = LlmErrorClassifier.classify(429, error)

        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(15, recoverable.retryAfterSeconds)
    }

    @Test
    fun `http 429 without Retry-After returns Recoverable with null retryAfter`() {
        val error = RuntimeException("HTTP 429 Too Many Requests")
        val result = LlmErrorClassifier.classify(429, error)

        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(null, recoverable.retryAfterSeconds)
    }

    @Test
    fun `http 5xx returns Recoverable`() {
        val error = RuntimeException("HTTP 500 Internal Server Error")
        val result = LlmErrorClassifier.classify(500, error)
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)

        val result503 = LlmErrorClassifier.classify(503, RuntimeException("Service Unavailable"))
        assertTrue(result503 is LlmErrorClassifier.LlmError.Recoverable)
    }

    @Test
    fun `JSON parse error message returns Recoverable`() {
        val error = RuntimeException("Unexpected JSON token at position 42")
        val result = LlmErrorClassifier.classify(200, error)
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }

    @Test
    fun `syntax error message returns Recoverable`() {
        val error = RuntimeException("syntax error at line 1")
        val result = LlmErrorClassifier.classify(200, error)
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }

    // ── LlmFatal ──────────────────────────────────────────────────

    @Test
    fun `http 401 returns LlmFatal`() {
        val error = RuntimeException("HTTP 401 Unauthorized")
        val result = LlmErrorClassifier.classify(401, error)
        assertTrue("Expected LlmFatal for 401", result is LlmErrorClassifier.LlmError.LlmFatal)
    }

    @Test
    fun `http 403 returns LlmFatal`() {
        val error = RuntimeException("HTTP 403 Forbidden")
        val result = LlmErrorClassifier.classify(403, error)
        assertTrue("Expected LlmFatal for 403", result is LlmErrorClassifier.LlmError.LlmFatal)
    }

    @Test
    fun `http 400 returns LlmFatal`() {
        val error = RuntimeException("HTTP 400 Bad Request")
        val result = LlmErrorClassifier.classify(400, error)
        assertTrue("Expected LlmFatal for 400", result is LlmErrorClassifier.LlmError.LlmFatal)
    }

    // ── Structural ─────────────────────────────────────────────────

    @Test
    fun `PipelineBlockingException returns Structural`() {
        val error = PipelineBlockingException("DB constraint violation", null)
        val result = LlmErrorClassifier.classify(null, error)
        assertTrue("Expected Structural", result is LlmErrorClassifier.LlmError.Structural)
    }

    @Test
    fun `Constraint in message returns Structural`() {
        val error = RuntimeException("Constraint violation: UNIQUE constraint failed")
        val result = LlmErrorClassifier.classify(null, error)
        assertTrue("Expected Structural for constraint message", result is LlmErrorClassifier.LlmError.Structural)
    }

    @Test
    fun `disk IO in message returns Structural`() {
        val error = RuntimeException("disk I/O error: No space left")
        val result = LlmErrorClassifier.classify(null, error)
        assertTrue("Expected Structural for disk I/O message", result is LlmErrorClassifier.LlmError.Structural)
    }

    @Test
    fun `Structural errors take priority over HTTP code`() {
        val error = PipelineBlockingException("Constraint violation", null)
        // Even with 500, should be Structural because PipelineBlockingException takes priority
        val result = LlmErrorClassifier.classify(500, error)
        assertTrue("Expected Structural even with HTTP 500", result is LlmErrorClassifier.LlmError.Structural)
    }

    // ── Edge cases ────────────────────────────────────────────────

    @Test
    fun `unknown http code defaults to Recoverable`() {
        val error = RuntimeException("Some error")
        val result = LlmErrorClassifier.classify(418, error) // I'm a teapot
        assertTrue("Unknown code should be Recoverable", result is LlmErrorClassifier.LlmError.Recoverable)
    }

    @Test
    fun `null message with httpCode returns Recoverable`() {
        val error = RuntimeException(null as String?)
        val result = LlmErrorClassifier.classify(502, error)
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }

    @Test
    fun `null message without httpCode returns Recoverable`() {
        val error = RuntimeException(null as String?)
        val result = LlmErrorClassifier.classify(null, error)
        assertTrue(result is LlmErrorClassifier.LlmError.Recoverable)
    }

    // ── extractRetryAfter (via classify with 429) ──────────────────

    @Test
    fun `Retry-After with equals sign is parsed`() {
        val error = RuntimeException("HTTP 429, Retry-After=30")
        val result = LlmErrorClassifier.classify(429, error)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(30, recoverable.retryAfterSeconds)
    }

    @Test
    fun `Retry-After with spaces is parsed`() {
        val error = RuntimeException("HTTP 429, Retry-After: 5")
        val result = LlmErrorClassifier.classify(429, error)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(5, recoverable.retryAfterSeconds)
    }

    @Test
    fun `non-numeric Retry-After returns null`() {
        val error = RuntimeException("Retry-After: later")
        val result = LlmErrorClassifier.classify(429, error)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(null, recoverable.retryAfterSeconds)
    }

    @Test
    fun `Retry-After with null message returns null`() {
        val error = RuntimeException(null as String?)
        val result = LlmErrorClassifier.classify(429, error)
        val recoverable = result as LlmErrorClassifier.LlmError.Recoverable
        assertEquals(null, recoverable.retryAfterSeconds)
    }
}
