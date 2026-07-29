package com.ak.contexta.domain.model

data class WordDetail(
    val wordId: Long,
    val spellingDisplay: String,
    val phoneticIpa: String?,
    val primarySense: WordSense?,
    val allSenses: List<WordSense>,
    val isInVocabulary: Boolean = false,
    val vocabularyEntryId: Long? = null
)

data class WordSense(
    val id: Long,
    val orderIndex: Int,
    val partOfSpeech: String,
    val chineseMeaning: String,
    val englishDefinition: String,
    val examples: List<ExampleSentence>
)

data class ExampleSentence(
    val id: Long,
    val orderIndex: Int,
    val sentenceEn: String,
    val sentenceZh: String,
    val isPrimary: Boolean
)
