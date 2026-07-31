package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "vocabulary_entry",
    foreignKeys = [
        ForeignKey(
            entity = WordEntity::class,
            parentColumns = ["id"],
            childColumns = ["word_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("word_id")]
)
data class VocabularyEntryEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "word_id")
    val wordId: Long,
    @ColumnInfo(name = "instance_number")
    val instanceNumber: Int = 1, // increments each time the same word is re-added
    @ColumnInfo(name = "status")
    val status: String = "NEW", // NEW | LEARNING | MASTERED
    @ColumnInfo(name = "correct_review_streak")
    val correctReviewStreak: Int = 0,
    @ColumnInfo(name = "mastered_at")
    val masteredAt: String? = null,
    @ColumnInfo(name = "deleted_at")
    val deletedAt: String? = null, // soft delete
    @ColumnInfo(name = "deleted_reason")
    val deletedReason: String? = null // "MANUAL_REMOVAL" | "MASTERED"
)
