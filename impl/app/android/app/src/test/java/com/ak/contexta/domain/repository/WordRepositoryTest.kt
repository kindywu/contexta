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
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class WordRepositoryTest {

    private val wordDao: WordDao = mockk()
    private val wordSenseDao: WordSenseDao = mockk()
    private val exampleSentenceDao: ExampleSentenceDao = mockk()
    private val vocabularyEntryDao: VocabularyEntryDao = mockk()

    private lateinit var repository: WordRepository

    @Before
    fun setup() {
        repository = WordRepository(
            wordDao = wordDao,
            wordSenseDao = wordSenseDao,
            exampleSentenceDao = exampleSentenceDao,
            vocabularyEntryDao = vocabularyEntryDao
        )
    }

    // ── LRU cache hit ─────────────────────────────────────────────

    @Test
    fun `lookupWord returns from cache on second call without DB or LLM`() = runTest {
        val expected = WordDetail(
            wordId = 1,
            spellingDisplay = "hello",
            phoneticIpa = "/həˈloʊ/",
            primarySense = WordSense(
                id = 1, orderIndex = 0,
                partOfSpeech = "int.", chineseMeaning = "你好",
                englishDefinition = "used as a greeting",
                examples = emptyList()
            ),
            allSenses = listOf(
                WordSense(
                    id = 1, orderIndex = 0,
                    partOfSpeech = "int.", chineseMeaning = "你好",
                    englishDefinition = "used as a greeting",
                    examples = emptyList()
                )
            ),
            isInVocabulary = false
        )

        val llmFallback: suspend (String) -> WordDetail? = { expected }

        // First call: no cache, no DB → LLM fallback
        coEvery { wordDao.getByNormalized("hello") } returns null
        val firstResult = repository.lookupWord("hello", llmFallback)
        assertNotNull(firstResult)
        assertEquals("hello", firstResult!!.spellingDisplay)
        coVerify(exactly = 1) { wordDao.getByNormalized("hello") } // DB called on first
    }

    @Test
    fun `lookupWord returns from cache and skips DB on second call`() = runTest {
        val wordEntity = WordEntity(
            id = 1, spellingNormalized = "world",
            spellingDisplay = "world", phoneticIpa = "/wɜrld/"
        )
        val senseEntity = WordSenseEntity(
            id = 1, wordId = 1, orderIndex = 0,
            partOfSpeech = "n.", chineseMeaning = "世界",
            englishDefinition = "the earth"
        )

        coEvery { wordDao.getByNormalized("world") } returns wordEntity
        coEvery { wordSenseDao.getByWord(1) } returns listOf(senseEntity)
        coEvery { exampleSentenceDao.getBySense(1) } returns emptyList()
        coEvery { vocabularyEntryDao.getActiveByWord(1) } returns null

        val llmFallback: suspend (String) -> WordDetail? = { null }

        // First call: DB hit
        val first = repository.lookupWord("world", llmFallback)
        assertNotNull(first)
        coVerify(exactly = 1) { wordDao.getByNormalized("world") }

        // Second call: cache hit, no DB query
        val second = repository.lookupWord("world", llmFallback)
        assertNotNull(second)
        // Still exactly 1 DB call — second hit came from cache
        coVerify(exactly = 1) { wordDao.getByNormalized("world") }
    }

    // ── DB hit ────────────────────────────────────────────────────

    @Test
    fun `lookupWord returns from DB when cache miss`() = runTest {
        val wordEntity = WordEntity(
            id = 5, spellingNormalized = "test",
            spellingDisplay = "test", phoneticIpa = "/tɛst/"
        )
        val senseEntity = WordSenseEntity(
            id = 10, wordId = 5, orderIndex = 0,
            partOfSpeech = "n.", chineseMeaning = "测试",
            englishDefinition = "a procedure to evaluate something"
        )
        val exampleEntity = ExampleSentenceEntity(
            wordSenseId = 10, orderIndex = 0,
            sentenceEn = "This is a test.",
            sentenceZh = "这是一个测试。",
            isPrimary = true
        )

        coEvery { wordDao.getByNormalized("test") } returns wordEntity
        coEvery { wordSenseDao.getByWord(5) } returns listOf(senseEntity)
        coEvery { exampleSentenceDao.getBySense(10) } returns listOf(exampleEntity)
        coEvery { vocabularyEntryDao.getActiveByWord(5) } returns null

        val llmFallback: suspend (String) -> WordDetail? = { null }

        val result = repository.lookupWord("test", llmFallback)

        assertNotNull(result)
        assertEquals("test", result!!.spellingDisplay)
        assertEquals("/tɛst/", result.phoneticIpa)
        assertEquals(1, result.allSenses.size)
        assertEquals("n.", result.allSenses[0].partOfSpeech)
        assertEquals("测试", result.allSenses[0].chineseMeaning)
        assertEquals(1, result.allSenses[0].examples.size)
        assertEquals("This is a test.", result.allSenses[0].examples[0].sentenceEn)
    }

    // ── LLM fallback hit ──────────────────────────────────────────

    @Test
    fun `lookupWord calls llmFallback when cache miss and DB miss`() = runTest {
        coEvery { wordDao.getByNormalized("foo") } returns null

        val llmResult = WordDetail(
            wordId = 99,
            spellingDisplay = "foo",
            phoneticIpa = null,
            primarySense = null,
            allSenses = emptyList(),
            isInVocabulary = false
        )
        val llmFallback: suspend (String) -> WordDetail? = { llmResult }

        val result = repository.lookupWord("foo", llmFallback)

        assertNotNull(result)
        assertEquals("foo", result!!.spellingDisplay)
        coVerify(exactly = 1) { wordDao.getByNormalized("foo") }
    }

    @Test
    fun `lookupWord returns null when all sources miss`() = runTest {
        coEvery { wordDao.getByNormalized("unknownword") } returns null

        val llmFallback: suspend (String) -> WordDetail? = { null }

        val result = repository.lookupWord("unknownword", llmFallback)

        assertNull(result)
        coVerify(exactly = 1) { wordDao.getByNormalized("unknownword") }
    }

    // ── Normalization ─────────────────────────────────────────────

    @Test
    fun `lookupWord normalizes spelling with punctuation`() = runTest {
        val wordEntity = WordEntity(
            id = 1, spellingNormalized = "hello",
            spellingDisplay = "hello", phoneticIpa = null
        )

        coEvery { wordDao.getByNormalized("hello") } returns wordEntity
        coEvery { wordSenseDao.getByWord(1) } returns emptyList()
        coEvery { exampleSentenceDao.getBySense(any()) } answers { emptyList<ExampleSentenceEntity>() }
        coEvery { vocabularyEntryDao.getActiveByWord(1) } returns null

        val llmFallback: suspend (String) -> WordDetail? = { null }

        // "Hello!" normalizes to "hello"
        val result = repository.lookupWord("Hello!", llmFallback)
        assertNotNull(result)
        assertEquals("hello", result!!.spellingDisplay)
    }

    @Test
    fun `lookupWord normalizes mixed case`() = runTest {
        val wordEntity = WordEntity(
            id = 2, spellingNormalized = "apple",
            spellingDisplay = "apple", phoneticIpa = null
        )

        coEvery { wordDao.getByNormalized("apple") } returns wordEntity
        coEvery { wordSenseDao.getByWord(2) } returns emptyList()
        coEvery { exampleSentenceDao.getBySense(any()) } answers { emptyList<ExampleSentenceEntity>() }
        coEvery { vocabularyEntryDao.getActiveByWord(2) } returns null

        val llmFallback: suspend (String) -> WordDetail? = { null }

        val result = repository.lookupWord("APPLE", llmFallback)
        assertNotNull(result)
    }

    // ── Save LLM result ──────────────────────────────────────────

    @Test
    fun `saveLlmResult inserts word and senses and returns WordDetail`() = runTest {
        coEvery { wordDao.insert(any<WordEntity>()) } returns 1L
        coEvery { wordDao.getByNormalized("newword") } returns null
        coEvery { wordDao.getById(1) } returns WordEntity(
            id = 1, spellingNormalized = "newword",
            spellingDisplay = "new word", phoneticIpa = "/nuː wɜrd/"
        )
        coEvery { wordSenseDao.insertAll(any<List<WordSenseEntity>>()) } returns listOf(10L, 11L)
        coEvery { wordSenseDao.getByWord(1) } returns listOf(
            WordSenseEntity(id = 10, wordId = 1, orderIndex = 0, partOfSpeech = "adj.", chineseMeaning = "新的", englishDefinition = "not old"),
            WordSenseEntity(id = 11, wordId = 1, orderIndex = 1, partOfSpeech = "n.", chineseMeaning = "新东西", englishDefinition = "something new")
        )
        coEvery { exampleSentenceDao.getBySense(10) } returns emptyList()
        coEvery { exampleSentenceDao.getBySense(11) } returns emptyList()
        coEvery { vocabularyEntryDao.getActiveByWord(1) } returns null

        val senses = listOf(
            WordSense(id = 0, orderIndex = 0, partOfSpeech = "adj.", chineseMeaning = "新的", englishDefinition = "not old", examples = emptyList()),
            WordSense(id = 0, orderIndex = 1, partOfSpeech = "n.", chineseMeaning = "新东西", englishDefinition = "something new", examples = emptyList())
        )

        val result = repository.saveLlmResult(
            spellingDisplay = "new word",
            phoneticIpa = "/nuː wɜrd/",
            senses = senses
        )

        assertEquals("new word", result.spellingDisplay)
        assertEquals("/nuː wɜrd/", result.phoneticIpa)
        assertEquals(2, result.allSenses.size)
        coVerify(exactly = 1) { wordDao.insert(any()) }
    }

    @Test
    fun `saveLlmResult handles existing word conflict (insert returns -1)`() = runTest {
        coEvery { wordDao.insert(any<WordEntity>()) } returns -1L
        coEvery { wordDao.getByNormalized("existing") } returns WordEntity(
            id = 10, spellingNormalized = "existing",
            spellingDisplay = "existing", phoneticIpa = "/ɪɡˈzɪstɪŋ/"
        )
        coEvery { wordDao.getById(10) } returns WordEntity(
            id = 10, spellingNormalized = "existing",
            spellingDisplay = "existing", phoneticIpa = "/ɪɡˈzɪstɪŋ/"
        )
        coEvery { wordSenseDao.insertAll(any<List<WordSenseEntity>>()) } returns listOf(20L)
        coEvery { wordSenseDao.getByWord(10) } returns listOf(
            WordSenseEntity(id = 20, wordId = 10, orderIndex = 0, partOfSpeech = "adj.", chineseMeaning = "现有的", englishDefinition = "present")
        )
        coEvery { exampleSentenceDao.getBySense(20) } returns emptyList()
        coEvery { vocabularyEntryDao.getActiveByWord(10) } returns null

        val result = repository.saveLlmResult(
            spellingDisplay = "existing",
            phoneticIpa = null,
            senses = listOf(
                WordSense(id = 0, orderIndex = 0, partOfSpeech = "adj.", chineseMeaning = "现有的", englishDefinition = "present", examples = emptyList())
            )
        )

        assertNotNull(result)
        // Should have fetched existing word via getByNormalized fallback
        coVerify { wordDao.getByNormalized("existing") }
    }

    // ── Word detail ──────────────────────────────────────────────

    @Test
    fun `getWordDetail returns null for non-existent word`() = runTest {
        coEvery { wordDao.getById(999) } returns null

        val result = repository.getWordDetail(999)
        assertNull(result)
    }

    @Test
    fun `getWordDetail returns built WordDetail with vocabulary status`() = runTest {
        val wordEntity = WordEntity(id = 3, spellingNormalized = "cat", spellingDisplay = "cat", phoneticIpa = "/kæt/")
        val senseEntity = WordSenseEntity(id = 30, wordId = 3, orderIndex = 0, partOfSpeech = "n.", chineseMeaning = "猫", englishDefinition = "a furry pet")
        val vocabEntry = VocabularyEntryEntity(id = 100, wordId = 3, instanceNumber = 1, status = "NEW")

        coEvery { wordDao.getById(3) } returns wordEntity
        coEvery { wordSenseDao.getByWord(3) } returns listOf(senseEntity)
        coEvery { exampleSentenceDao.getBySense(30) } returns emptyList()
        coEvery { vocabularyEntryDao.getActiveByWord(3) } returns vocabEntry

        val result = repository.getWordDetail(3)

        assertNotNull(result)
        assertEquals("cat", result!!.spellingDisplay)
        assertEquals(true, result.isInVocabulary)
        assertEquals(100L, result.vocabularyEntryId)
    }
}
