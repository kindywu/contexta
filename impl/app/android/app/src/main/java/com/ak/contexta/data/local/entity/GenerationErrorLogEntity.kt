package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.ak.contexta.data.local.ContextaTypeConverters

/**
 * 生成错误流水账（db:TYPE 流水账）。
 *
 * 记录生成管道中发生的错误事件（快照），而不是当前状态。
 * 状态留在 [ArticleBatchEntity] / [ArticleEntity] 的 status 字段，
 * 错误详情（error_code / error_message / error_help）移入本表，可追溯历史。
 *
 * 违反 3NF 说明：本表冗余存储 error_message 等可读文本，而非仅存错误码外键。
 * 理由：错误消息来自 LLM / 异常，无独立字典表可引用，直接冗余是唯一合理表达。—— db:NF
 */
@Entity(
    tableName = "generation_error_log",
    indices = [
        Index(value = ["entity_type", "entity_id"]),
        Index(value = ["created_at"])
    ]
)
data class GenerationErrorLogEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "entity_type")
    val entityType: String, // "BATCH" | "ARTICLE"
    @ColumnInfo(name = "entity_id")
    val entityId: Long,
    @ColumnInfo(name = "error_code")
    val errorCode: String,
    @ColumnInfo(name = "error_message")
    val errorMessage: String,
    @ColumnInfo(name = "error_help")
    val errorHelp: String? = null,
    @ColumnInfo(name = "retry_count")
    val retryCount: Int = 0, // 快照：错误发生时的重试次数
    @ColumnInfo(name = "created_at")
    val createdAt: String = ContextaTypeConverters.currentDateTimeString(),
    @ColumnInfo(name = "notified_at")
    val notifiedAt: Long? = null // 飞书告警送达时间（Unix millis）；null = 未通知，启动时补发
)
