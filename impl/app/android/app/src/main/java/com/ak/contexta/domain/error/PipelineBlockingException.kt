package com.ak.contexta.domain.error

/**
 * 代码级结构性错误（DB 约束冲突、序列化异常等），
 * 应触发 FATAL article 状态和 BLOCKED pipeline 状态。
 */
class PipelineBlockingException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)
