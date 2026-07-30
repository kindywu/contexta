package com.ak.contexta.domain.repository

import com.ak.contexta.domain.model.VocabWord
import kotlinx.coroutines.flow.Flow

interface VocabularyRepository {
    /** Observe active (non-deleted, non-mastered) vocabulary entries */
    fun observeActive(): Flow<List<VocabWord>>

    /** Get active entries count */
    suspend fun getActiveCount(): Int

    /** One-shot: get all active vocab words mapped to domain models */
    suspend fun getActiveWords(): List<VocabWord>

    /** Add word to vocabulary (creates new instance) */
    suspend fun addWord(wordId: Long): Boolean

    /** Mark word as "known" — increment streak, auto-master if streak reaches threshold */
    suspend fun markCorrect(entryId: Long, masteryThreshold: Int = 1)

    /** Mark word as "not known" — reset streak */
    suspend fun markIncorrect(entryId: Long)

    /** Remove word from vocabulary (soft delete) */
    suspend fun removeWord(entryId: Long, reason: String = "MANUAL_REMOVAL")

    /** Count distinct words ever added */
    suspend fun countDistinctWords(): Int
}
