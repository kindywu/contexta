package com.ak.contexta.data.repository

import com.ak.contexta.data.local.dao.VocabularyEntryDao
import com.ak.contexta.data.local.dao.WordDao
import com.ak.contexta.data.local.entity.VocabularyEntryEntity
import com.ak.contexta.domain.model.VocabStatus
import com.ak.contexta.domain.model.VocabWord
import com.ak.contexta.domain.model.WordSense
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import com.ak.contexta.domain.time.TimeProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VocabularyRepositoryImpl @Inject constructor(
    private val vocabularyEntryDao: VocabularyEntryDao,
    private val wordRepository: WordRepository,
    private val wordDao: WordDao,
    private val timeProvider: TimeProvider
) : VocabularyRepository {

    override fun observeActive(): Flow<List<VocabWord>> =
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

    override suspend fun getActiveCount(): Int =
        vocabularyEntryDao.getActive().size

    override suspend fun getActiveWords(): List<VocabWord> {
        return vocabularyEntryDao.getActive().mapNotNull { entry ->
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

    override suspend fun addWord(wordId: Long): Long? {
        val existing = vocabularyEntryDao.getActiveByWord(wordId)
        if (existing != null) return null

        val nextInstance = vocabularyEntryDao.nextInstanceNumber(wordId)
        val entry = VocabularyEntryEntity(
            wordId = wordId,
            instanceNumber = nextInstance,
            status = "NEW"
        )
        return vocabularyEntryDao.insert(entry)
    }

    override suspend fun markCorrect(entryId: Long, masteryThreshold: Int) {
        if (masteryThreshold <= 1) {
            val now = timeProvider.nowDateTimeString()
            vocabularyEntryDao.markMastered(entryId, now)
        } else {
            vocabularyEntryDao.markCorrectReview(entryId, "LEARNING")
            val entry = vocabularyEntryDao.getById(entryId)
            if (entry != null && entry.correctReviewStreak >= masteryThreshold) {
                vocabularyEntryDao.markMastered(entryId, timeProvider.nowDateTimeString())
            }
        }
    }

    override suspend fun markIncorrect(entryId: Long) {
        vocabularyEntryDao.resetStreak(entryId)
    }

    override suspend fun removeWord(entryId: Long, reason: String) {
        vocabularyEntryDao.softDelete(entryId, reason, timeProvider.nowDateTimeString())
    }

    override suspend fun countDistinctWords(): Int =
        vocabularyEntryDao.countDistinctWords()
}
