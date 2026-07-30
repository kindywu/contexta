package com.ak.contexta.data.repository

import com.ak.contexta.data.local.dao.ExampleSentenceDao
import com.ak.contexta.data.local.dao.VocabularyEntryDao
import com.ak.contexta.data.local.dao.WordDao
import com.ak.contexta.data.local.dao.WordSenseDao
import com.ak.contexta.data.local.entity.ExampleSentenceEntity
import com.ak.contexta.data.local.entity.WordEntity
import com.ak.contexta.data.local.entity.WordSenseEntity
import com.ak.contexta.domain.model.ExampleSentence
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.domain.model.WordSense
import com.ak.contexta.domain.repository.WordRepository
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.util.LinkedHashMap
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class WordRepositoryImpl @Inject constructor(
    private val wordDao: WordDao,
    private val wordSenseDao: WordSenseDao,
    private val exampleSentenceDao: ExampleSentenceDao,
    private val vocabularyEntryDao: VocabularyEntryDao
) : WordRepository {

    // LRU cache: up to 50 entries, keyed by normalized spelling
    private val lruCache = object : LinkedHashMap<String, WordDetail>(50, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, WordDetail>): Boolean =
            size > 50
    }

    // Semaphore for concurrent lookups (permits = 3)
    private val lookupSemaphore = Semaphore(3)

    override suspend fun lookupWord(
        spelling: String,
        llmFallback: suspend (String) -> WordDetail?
    ): WordDetail? = lookupSemaphore.withPermit {
        val normalized = WordRepository.normalize(spelling)

        // 1. LRU cache
        lruCache[normalized]?.let { return@withPermit it }

        // 2. Local DB
        val existingWord = wordDao.getByNormalized(normalized)
        if (existingWord != null) {
            val detail = buildWordDetail(existingWord)
            lruCache[normalized] = detail
            return@withPermit detail
        }

        // 3. LLM fallback (external caller provides this)
        val detail = llmFallback(spelling)
        if (detail != null) {
            lruCache[normalized] = detail
        }
        return@withPermit detail
    }

    override suspend fun saveLlmResult(
        spellingDisplay: String,
        phoneticIpa: String?,
        senses: List<WordSense>,
        normalized: String
    ): WordDetail {
        val wordEntity = WordEntity(
            spellingNormalized = normalized,
            spellingDisplay = spellingDisplay,
            phoneticIpa = phoneticIpa
        )
        val wordId = wordDao.insert(wordEntity).let { id ->
            if (id == -1L) {
                wordDao.getByNormalized(normalized)!!.id
            } else id
        }

        val senseEntities = senses.mapIndexed { index, sense ->
            WordSenseEntity(
                wordId = wordId,
                orderIndex = sense.orderIndex.takeIf { it > 0 } ?: index,
                partOfSpeech = sense.partOfSpeech,
                chineseMeaning = sense.chineseMeaning,
                englishDefinition = sense.englishDefinition
            )
        }
        val senseIds = wordSenseDao.insertAll(senseEntities)

        senseEntities.zip(senses).forEachIndexed { senseIndex, (entity, sense) ->
            val senseId = senseIds.getOrNull(senseIndex)
                ?: wordSenseDao.insert(entity)
            val exampleEntities = sense.examples.mapIndexed { exIndex, ex ->
                ExampleSentenceEntity(
                    wordSenseId = senseId,
                    orderIndex = ex.orderIndex.takeIf { it > 0 } ?: exIndex,
                    sentenceEn = ex.sentenceEn,
                    sentenceZh = ex.sentenceZh,
                    isPrimary = ex.isPrimary
                )
            }
            if (exampleEntities.isNotEmpty()) {
                exampleSentenceDao.insertAll(exampleEntities)
            }
        }

        val word = wordDao.getById(wordId) ?: error("Failed to read back word $wordId")
        val detail = buildWordDetail(word)
        lruCache[normalized] = detail
        return detail
    }

    override suspend fun getWordDetail(wordId: Long): WordDetail? {
        val word = wordDao.getById(wordId) ?: return null
        return buildWordDetail(word)
    }

    override suspend fun getWordDetails(wordIds: List<Long>): Map<Long, WordDetail> {
        val words = wordDao.getByIds(wordIds)
        return words.associate { it.id to buildWordDetail(it) }
    }

    /** Build full WordDetail from a WordEntity (with senses + examples) */
    private suspend fun buildWordDetail(word: WordEntity): WordDetail {
        val senses = wordSenseDao.getByWord(word.id)
        val senseModels = senses.map { sense ->
            val examples = exampleSentenceDao.getBySense(sense.id).map { ex ->
                ExampleSentence(
                    id = ex.id,
                    orderIndex = ex.orderIndex,
                    sentenceEn = ex.sentenceEn,
                    sentenceZh = ex.sentenceZh,
                    isPrimary = ex.isPrimary
                )
            }
            WordSense(
                id = sense.id,
                orderIndex = sense.orderIndex,
                partOfSpeech = sense.partOfSpeech,
                chineseMeaning = sense.chineseMeaning,
                englishDefinition = sense.englishDefinition,
                examples = examples
            )
        }

        val vocabEntry = vocabularyEntryDao.getActiveByWord(word.id)

        return WordDetail(
            wordId = word.id,
            spellingDisplay = word.spellingDisplay,
            phoneticIpa = word.phoneticIpa,
            primarySense = senseModels.firstOrNull(),
            allSenses = senseModels,
            isInVocabulary = vocabEntry != null,
            vocabularyEntryId = vocabEntry?.id
        )
    }
}
