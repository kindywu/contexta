package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "generation_pipeline_status")
data class GenerationPipelineStatusEntity(
    @PrimaryKey
    val id: Int = 1, // singleton, always 1
    @ColumnInfo(name = "is_blocked")
    val isBlocked: Boolean = false,
    @ColumnInfo(name = "blocked_reason")
    val blockedReason: String? = null,
    @ColumnInfo(name = "blocked_at")
    val blockedAt: Long? = null,
    @ColumnInfo(name = "blocked_app_version_code")
    val blockedAppVersionCode: Int? = null
)
