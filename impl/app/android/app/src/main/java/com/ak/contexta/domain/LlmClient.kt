package com.ak.contexta.domain

/**
 * LLM 客户端接口，由 data 层实现。
 */
interface LlmClient {

    data class LlmResult(
        val content: String,
        val retryCount: Int
    )

    /**
     * 调用 LLM 生成内容。
     * @return LLM 响应内容和重试次数
     * @throws LlmFatalException LLM 服务级不可恢复错误
     * @throws LlmRecoverableExhaustedException 可恢复错误耗尽所有重试
     * @throws [com.ak.contexta.domain.error.PipelineBlockingException] 代码级结构性错误
     */
    suspend fun call(
        systemPrompt: String,
        userPrompt: String,
        timeoutMs: Long = 120_000L
    ): LlmResult
}
