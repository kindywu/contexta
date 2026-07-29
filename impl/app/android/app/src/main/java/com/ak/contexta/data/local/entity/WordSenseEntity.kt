package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "word_sense",
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
data class WordSenseEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "word_id")
    val wordId: Long,
    @ColumnInfo(name = "order_index")
    val orderIndex: Int, // display order, context-matching sense first (0)
    @ColumnInfo(name = "part_of_speech")
    val partOfSpeech: String, // e.g. "n.", "v."
    @ColumnInfo(name = "chinese_meaning")
    val chineseMeaning: String,
    @ColumnInfo(name = "english_definition")
    val englishDefinition: String
)
