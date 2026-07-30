package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * 每日学习记录表。
 *
 * 每天一条记录，记录用户在 [learningDate] 学了哪个批次（[refBatchId]）的文章，
 * 以及当时的用户设置快照（[dailyCountSnapshot]）。
 *
 * [learningDate] 是 PRIMARY KEY，确保每天最多一条记录。
 */
@Entity(
    tableName = "daily_learning",
    foreignKeys = [
        ForeignKey(
            entity = ArticleBatchEntity::class,
            parentColumns = ["id"],
            childColumns = ["ref_batch_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["ref_batch_id"])
    ]
)
data class DailyLearningEntity(
    @PrimaryKey
    @ColumnInfo(name = "learning_date")
    val learningDate: String, // ISO date, UNIQUE (因 PRIMARY KEY 而隐式唯一)
    @ColumnInfo(name = "ref_batch_date")
    val refBatchDate: String, // article_batch.generated_on
    @ColumnInfo(name = "ref_batch_id")
    val refBatchId: Long,
    @ColumnInfo(name = "daily_count_snapshot")
    val dailyCountSnapshot: Int
)
