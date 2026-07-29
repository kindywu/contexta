package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "config_change_log")
data class ConfigChangeLogEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "field_name")
    val fieldName: String, // currently only "daily_article_count"
    @ColumnInfo(name = "old_value")
    val oldValue: String,
    @ColumnInfo(name = "new_value")
    val newValue: String,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)
