package com.ak.contexta.domain.model

/**
 * 文章生成错误事件（来自 generation_error_log 流水账）。
 *
 * [status] 是实体表的状态投影（如 "FAILED" / "TIMEOUT" / "FATAL"），
 * 用于 UI 判断是否可以重试；实体已删除时为 null。
 */
data class GenerationError(
    val id: Long, // generation_error_log 主键（补发告警后回写 notified_at 用）
    val entityId: Long,
    val entityType: String = "ARTICLE", // "ARTICLE" | "BATCH"
    val errorCode: String,
    val errorMessage: String,
    val errorHelp: String?,
    val retryCount: Int,
    val createdAt: String,
    val status: String? = null
)
