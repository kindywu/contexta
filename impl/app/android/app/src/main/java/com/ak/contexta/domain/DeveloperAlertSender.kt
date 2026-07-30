package com.ak.contexta.domain

import com.ak.contexta.domain.error.AppError

/**
 * 错误上下文，由 Use Case 层在捕获异常时构造。
 * 所有字段由调用方显式传入，保持 domain 纯净。
 */
data class ErrorContext(
    val batchId: Long? = null,
    val articleId: Long? = null,
    val appVersion: Int = 0,
    val timestamp: Long  // 调用方通过 TimeProvider.nowMillis() 传入
)

/**
 * 开发者通知接口。
 * 仅用于不可恢复错误（LlmFatal 和 Structural），通知失败不应影响主流程。
 */
interface DeveloperAlertSender {
    /**
     * 发送 LLM 不可恢复错误通知给开发者。
     * 用于 LlmFatal 错误：API Key 失效、LLM 账号欠费、存储空间不足等。
     */
    suspend fun sendLlmFatalError(error: AppError.LlmFatal, context: ErrorContext)

    /**
     * 发送结构性错误通知给开发者。
     * 用于 Structural 错误（代码级 bug）。
     */
    suspend fun sendStructuralError(error: AppError.Structural, context: ErrorContext)
}
