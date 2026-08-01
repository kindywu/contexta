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
 * 用于不可恢复或需要关注的错误，通知失败不应影响主流程。
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

    /**
     * 发送文章生成失败通知。
     * 用于 TIMEOUT / FAILED / FATAL 等非 SUCCESS 终态，
     * 帮助开发者发现 LLM 服务不稳定或超时问题。
     */
    suspend fun sendArticleFailure(
        status: String,
        errorCode: String,
        errorMessage: String,
        context: ErrorContext
    )

    /**
     * 发送批次生成完成通知。
     * 批次所有文章生成成功时发送，作为心跳/状态确认。
     * [batchGeneratedOn] / [batchDifficulty] 用于通知中展示批次日期与难度（可为 null，通知中显示 ?）。
     */
    suspend fun sendBatchReady(
        batchId: Long,
        articleCount: Int,
        batchGeneratedOn: String?,
        batchDifficulty: String?,
        context: ErrorContext
    )
}
