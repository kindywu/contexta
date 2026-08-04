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

/**
 * 协程级超时（withTimeoutOrNull 超时，LLM_TIMEOUT_MS）。
 *
 * 与 [LlmRecoverableExhaustedException] 的区别：
 * - 后者是网络/服务层错误经过重试后耗尽（每次尝试有自己的超时）；
 * - 本异常是一次调用达到总预算超时，直接放弃。
 * 由 GenerateArticlesUseCase 分类为 TIMEOUT / LLM_TIMEOUT，而非 UNEXPECTED。
 */
class LlmTimeoutException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)
