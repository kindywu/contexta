package com.ak.contexta.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "word",
    indices = [Index(value = ["spelling_normalized"], unique = true)]
)
data class WordEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    @ColumnInfo(name = "spelling_normalized")
    val spellingNormalized: String, // lowercase + trimmed, used for lookup, never displayed
    @ColumnInfo(name = "spelling_display")
    val spellingDisplay: String, // canonical form displayed to user
    @ColumnInfo(name = "phonetic_ipa")
    val phoneticIpa: String? = null
)
