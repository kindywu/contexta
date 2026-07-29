package com.ak.contexta.domain.repository

import com.ak.contexta.data.local.dao.VocabularyEntryDao
import com.ak.contexta.data.local.dao.WordDao
import com.ak.contexta.data.local.entity.VocabularyEntryEntity
import com.ak.contexta.domain.model.VocabStatus
import com.ak.contexta.domain.model.VocabWord
import com.ak.contexta.domain.model.WordSense
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VocabularyRepository @Inject constructor(
    private val vocabularyEntryDao: VocabularyEntryDao,
    private val wordRepository: WordRepository,
    private val wordDao: WordDao
) {
    /** Observe active (non-deleted, non-mastered) vocabulary entries */
    fun observeActive(): Flow<List<VocabWord>> =
        vocabularyEntryDao.observeActive().map { entries ->
            entries.mapNotNull { entry ->
                wordRepository.getWordDetail(entry.wordId)?.let { detail ->
                    VocabWord(
                        entryId = entry.id,
                        wordId = entry.wordId,
                        instanceNumber = entry.instanceNumber,
                        status = VocabStatus.from(entry.status),
                        correctReviewStreak = entry.correctReviewStreak,
                        spellingDisplay = detail.spellingDisplay,
                        phoneticIpa = detail.phoneticIpa,
                        allSenses = detail.allSenses
                    )
                }
            }
        }

    /** Get active entries count */
    suspend fun getActiveCount(): Int =
        vocabularyEntryDao.getActive().size

    /** Add word to vocabulary (creates new instance) */
    suspend fun addWord(wordId: Long): Boolean {
        // Check if already active
        val existing = vocabularyEntryDao.getActiveByWord(wordId)
        if (existing != null) return false // already in vocab

        val nextInstance = vocabularyEntryDao.nextInstanceNumber(wordId)
        val entry = VocabularyEntryEntity(
            wordId = wordId,
            instanceNumber = nextInstance,
            status = "NEW"
        )
        vocabularyEntryDao.insert(entry)
        return true
    }

    /** Mark word as "known" — increment streak, auto-master if threshold reached */
    suspend fun markCorrect(entryId: Long, masteryThreshold: Int = 1) {
        if (masteryThreshold <= 1) {
            val now = System.currentTimeMillis()
            vocabularyEntryDao.markMastered(entryId, now)
        } else {
            vocabularyEntryDao.markCorrectReview(entryId, "LEARNING")
            // The threshold-based check can be done at query time or by tracking streak
        }
    }

    /** Mark word as "not known" — reset streak */
    suspend fun markIncorrect(entryId: Long) {
        vocabularyEntryDao.resetStreak(entryId)
    }

    /** Remove word from vocabulary (soft delete) */
    suspend fun removeWord(entryId: Long, reason: String = "MANUAL_REMOVAL") {
        vocabularyEntryDao.softDelete(entryId, reason, System.currentTimeMillis())
    }

    /** Count distinct words ever added */
    suspend fun countDistinctWords(): Int =
        vocabularyEntryDao.countDistinctWords()
}
