package com.ak.contexta.domain.error

/**
 * 统一错误类型，分为三类：
 * - [Recoverable]：可自动重试（网络超时、限流、服务端错误等）
 * - [LlmFatal]：LLM 服务级不可恢复（认证失败、内容策略拒绝等），需开发者介入
 * - [Structural]：代码级 bug（DB 约束冲突、序列化异常等），阻塞 pipeline
 */
sealed class AppError {
    /** 可恢复错误 — 自动重试，耗尽后用户可手动重试 */
    data class Recoverable(
        val code: RecoverableCode,
        val message: String,
        val cause: Throwable? = null,
        val retryAfterSeconds: Int? = null
    ) : AppError()

    /** LLM 不可恢复 — 服务级错误（换 API Key、改设置等），需开发者介入 */
    data class LlmFatal(
        val code: LlmFatalCode,
        val message: String,
        val cause: Throwable? = null
    ) : AppError()

    /** 结构性错误 — 代码 bug，需开发者介入 */
    data class Structural(
        val code: StructuralCode,
        val message: String,
        val cause: Throwable? = null
    ) : AppError()
}

enum class RecoverableCode {
    NETWORK_TIMEOUT,
    RATE_LIMITED,
    SERVER_ERROR,
    JSON_PARSE_FAILED,
    LLM_TIMEOUT
}

enum class LlmFatalCode {
    AUTH_FAILED,        // 401/403
    BAD_REQUEST,        // 400
    CONTENT_POLICY,     // 内容被拒绝
    EMPTY_RESPONSE      // LLM 返回空内容
}

enum class StructuralCode {
    DB_CONSTRAINT_VIOLATION,
    SERIALIZATION_ERROR,
    DISK_IO_ERROR,
    ILLEGAL_STATE,
    UNEXPECTED_ERROR
}
