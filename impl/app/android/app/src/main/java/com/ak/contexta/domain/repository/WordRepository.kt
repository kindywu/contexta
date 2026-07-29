package com.ak.contexta.domain.repository

import com.ak.contexta.data.local.dao.ExampleSentenceDao
import com.ak.contexta.data.local.dao.VocabularyEntryDao
import com.ak.contexta.data.local.dao.WordDao
import com.ak.contexta.data.local.dao.WordSenseDao
import com.ak.contexta.data.local.entity.ExampleSentenceEntity
import com.ak.contexta.data.local.entity.VocabularyEntryEntity
import com.ak.contexta.data.local.entity.WordEntity
import com.ak.contexta.data.local.entity.WordSenseEntity
import com.ak.contexta.domain.model.ExampleSentence
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.domain.model.WordSense
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.util.LinkedHashMap
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class WordRepository @Inject constructor(
    private val wordDao: WordDao,
    private val wordSenseDao: WordSenseDao,
    private val exampleSentenceDao: ExampleSentenceDao,
    private val vocabularyEntryDao: VocabularyEntryDao
) {
    // LRU cache: up to 50 entries, keyed by normalized spelling
    private val lruCache = object : LinkedHashMap<String, WordDetail>(50, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, WordDetail>): Boolean =
            size > 50
    }

    // Semaphore for concurrent lookups (permits = 3)
    private val lookupSemaphore = Semaphore(3)

    /**
     * Synchronous (suspend) word lookup:
     * 1. LRU cache → immediate return
     * 2. Local DB → cache + return
     * 3. LLM call (external) → write DB → cache + return
     *
     * The LLM part is handled by a caller-provided [llmFallback] lambda,
     * allowing the repository to stay testable without a real network client.
     */
    suspend fun lookupWord(
        spelling: String,
        llmFallback: suspend (String) -> WordDetail?
    ): WordDetail? = lookupSemaphore.withPermit {
        val normalized = normalize(spelling)

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

    /** Persist an LLM result into the DB */
    suspend fun saveLlmResult(
        spellingDisplay: String,
        phoneticIpa: String?,
        senses: List<WordSense>,
        normalized: String = normalize(spellingDisplay)
    ): WordDetail {
        val wordEntity = WordEntity(
            spellingNormalized = normalized,
            spellingDisplay = spellingDisplay,
            phoneticIpa = phoneticIpa
        )
        val wordId = wordDao.insert(wordEntity).let { id ->
            if (id == -1L) {
                // Already existed (IGNORE conflict), fetch it
                wordDao.getByNormalized(normalized)!!.id
            } else id
        }

        // Insert senses
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

        // Insert example sentences
        senseEntities.zip(senses).forEachIndexed { senseIndex, (entity, sense) ->
            val senseId = senseIds.getOrNull(senseIndex)
                ?: wordSenseDao.insert(entity) // fallback if insertAll returned empty list
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

    /** Get a WordDetail by word ID (for vocabulary review) */
    suspend fun getWordDetail(wordId: Long): WordDetail? {
        val word = wordDao.getById(wordId) ?: return null
        return buildWordDetail(word)
    }

    /** Get word details for multiple word IDs */
    suspend fun getWordDetails(wordIds: List<Long>): Map<Long, WordDetail> {
        val words = wordDao.getByIds(wordIds)
        return words.associate { it.id to buildWordDetail(it) }
    }

    /** Build full WordDetail from a WordEntity (with senses + examples) */
    suspend fun buildWordDetail(word: WordEntity): WordDetail {
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

    companion object {
        fun normalize(spelling: String): String {
            return spelling.trim().lowercase().trimEnd('.', ',', '!', '?', ';', ':', '"', '\'', ')', ']')
                .trimStart('"', '\'', '(', '[')
        }
    }
}
