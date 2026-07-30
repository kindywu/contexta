package com.ak.contexta.domain.repository

import com.ak.contexta.domain.model.ExampleSentence
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.domain.model.WordSense

interface WordRepository {
    /**
     * Synchronous (suspend) word lookup:
     * 1. LRU cache → immediate return
     * 2. Local DB → cache + return
     * 3. LLM call (external) → write DB → cache + return
     */
    suspend fun lookupWord(
        spelling: String,
        llmFallback: suspend (String) -> WordDetail?
    ): WordDetail?

    /** Persist an LLM result into the DB */
    suspend fun saveLlmResult(
        spellingDisplay: String,
        phoneticIpa: String?,
        senses: List<WordSense>,
        normalized: String = normalize(spellingDisplay)
    ): WordDetail

    /** Get a WordDetail by word ID (for vocabulary review) */
    suspend fun getWordDetail(wordId: Long): WordDetail?

    /** Get word details for multiple word IDs */
    suspend fun getWordDetails(wordIds: List<Long>): Map<Long, WordDetail>

    companion object {
        fun normalize(spelling: String): String {
            return spelling.trim().lowercase()
                .trimEnd('.', ',', '!', '?', ';', ':', '"', '\'', ')', ']')
                .trimStart('"', '\'', '(', '[')
        }
    }
}
