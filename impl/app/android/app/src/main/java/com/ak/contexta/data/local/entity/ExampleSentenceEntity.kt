package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "example_sentence",
    foreignKeys = [
        ForeignKey(
            entity = WordSenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["word_sense_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("word_sense_id")]
)
data class ExampleSentenceEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "word_sense_id")
    val wordSenseId: Long,
    @ColumnInfo(name = "order_index")
    val orderIndex: Int,
    @ColumnInfo(name = "sentence_en")
    val sentenceEn: String,
    @ColumnInfo(name = "sentence_zh")
    val sentenceZh: String,
    @ColumnInfo(name = "is_primary")
    val isPrimary: Boolean = false // true = context-matching example from the original article
)
