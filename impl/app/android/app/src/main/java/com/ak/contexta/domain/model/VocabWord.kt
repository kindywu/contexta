package com.ak.contexta.domain.model

data class VocabWord(
    val entryId: Long,
    val wordId: Long,
    val instanceNumber: Int,
    val status: VocabStatus,
    val correctReviewStreak: Int,
    val spellingDisplay: String,
    val phoneticIpa: String?,
    val allSenses: List<WordSense>
)

enum class VocabStatus(val value: String) {
    NEW("NEW"),
    LEARNING("LEARNING"),
    MASTERED("MASTERED");

    companion object {
        fun from(value: String): VocabStatus =
            entries.firstOrNull { it.value == value } ?: NEW
    }
}
