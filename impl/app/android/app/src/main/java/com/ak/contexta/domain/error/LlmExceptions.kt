package com.ak.contexta.domain.error

/** Non-recoverable LLM-side error (auth, bad request, content policy) */
class LlmFatalException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)

/** Recoverable error that exhausted all retries */
class LlmRecoverableExhaustedException(
    message: String,
    cause: Throwable? = null,
    val attempts: Int = 0
) : Exception(message, cause)
