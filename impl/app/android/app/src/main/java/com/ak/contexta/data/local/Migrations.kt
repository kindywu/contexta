package com.ak.contexta.data.local

import androidx.room.migration.Migration

/**
 * 产品尚未发布，所有 migration 记录已清空。
 * 数据库版本号重置为 1，通过 [fallbackToDestructiveMigration] 处理旧数据。
 *
 * 发布后在此处添加真实 migration。
 */
object Migrations {
    val ALL: Array<Migration> = emptyArray()
}
