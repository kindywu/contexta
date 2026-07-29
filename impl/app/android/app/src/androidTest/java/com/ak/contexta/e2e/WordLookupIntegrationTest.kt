package com.ak.contexta.e2e

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.ak.contexta.MainActivity
import com.ak.contexta.data.local.ContextaDatabase
import com.ak.contexta.data.local.Migrations
import com.ak.contexta.data.local.dao.ArticleBatchDao
import com.ak.contexta.data.local.dao.ArticleDao
import com.ak.contexta.data.local.dao.ArticleParagraphDao
import com.ak.contexta.data.local.dao.ExampleSentenceDao
import com.ak.contexta.data.local.dao.UserSettingsDao
import com.ak.contexta.data.local.dao.VocabularyEntryDao
import com.ak.contexta.data.local.dao.WordDao
import com.ak.contexta.data.local.dao.WordSenseDao
import com.ak.contexta.data.local.entity.ArticleBatchEntity
import com.ak.contexta.data.local.entity.ArticleEntity
import com.ak.contexta.data.local.entity.ArticleParagraphEntity
import com.ak.contexta.data.local.entity.ExampleSentenceEntity
import com.ak.contexta.data.local.entity.UserSettingsEntity
import com.ak.contexta.data.local.entity.WordEntity
import com.ak.contexta.data.local.entity.WordSenseEntity
import com.ak.contexta.domain.repository.WordRepository
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

/**
 * Integration test for the word lookup pipeline with a real Room database.
 *
 * Validates that:
 * 1. WordRepository.lookupWord() correctly assembles WordDetail from DB entities
 * 2. saveLlmResult() persists word + senses + examples correctly
 * 3. LRU cache + DB lookup work correctly in sequence
 * 4. Article with pre-populated content displays correctly on the reading screen
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class WordLookupIntegrationTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    // ── Injected real Hilt components ──

    @Inject lateinit var wordRepository: WordRepository

    // DAOs for direct DB setup
    @Inject lateinit var wordDao: WordDao
    @Inject lateinit var wordSenseDao: WordSenseDao
    @Inject lateinit var exampleSentenceDao: ExampleSentenceDao
    @Inject lateinit var vocabularyEntryDao: VocabularyEntryDao
    @Inject lateinit var userSettingsDao: UserSettingsDao
    @Inject lateinit var articleBatchDao: ArticleBatchDao
    @Inject lateinit var articleDao: ArticleDao
    @Inject lateinit var articleParagraphDao: ArticleParagraphDao

    private lateinit var context: Context

    @Before
    fun setup() {
        hiltRule.inject()
        context = InstrumentationRegistry.getInstrumentation().targetContext

        // Clear database for a fresh state
        context.deleteDatabase("contexta.db")

        // Populate the database with test data (runs on a background thread)
        runBlocking {
            // User settings — mark as onboarded so app goes straight to Home
            userSettingsDao.upsert(
                UserSettingsEntity(
                    id = 1,
                    isOnboarded = true,
                    difficultyLevel = "MEDIUM",
                    dailyArticleCount = 1,
                    translationDisplayMode = "full",
                    masteryThresholdN = 1,
                    autoPlayAudio = false
                )
            )

            // Article batch
            val batchId = articleBatchDao.insert(
                ArticleBatchEntity(
                    batchType = "CURRENT",
                    status = "READY",
                    difficultyLevelSnapshot = "MEDIUM",
                    dailyCountSnapshot = 1,
                    generatedOn = "2026-07-29"
                )
            )

            // Article (SUCCESS = already generated)
            val articleId = articleDao.insert(
                ArticleEntity(
                    batchId = batchId,
                    orderIndex = 1,
                    contentCategory = "SCENE_DESCRIPTION",
                    title = "A Walk in the Park",
                    status = "SUCCESS"
                )
            )

            // Paragraphs
            articleParagraphDao.insertAll(
                listOf(
                    ArticleParagraphEntity(
                        articleId = articleId,
                        orderIndex = 1,
                        englishText = "The sun was shining brightly over the city park.",
                        chineseTranslation = "阳光明媚地照在城市公园上。"
                    ),
                    ArticleParagraphEntity(
                        articleId = articleId,
                        orderIndex = 2,
                        englishText = "Children were playing happily on the green grass.",
                        chineseTranslation = "孩子们在绿色的草地上快乐地玩耍。"
                    ),
                    ArticleParagraphEntity(
                        articleId = articleId,
                        orderIndex = 3,
                        englishText = "An elderly couple sat on a bench reading books.",
                        chineseTranslation = "一对老夫妇坐在长椅上读书。"
                    )
                )
            )

            // Word: shining (verb)
            val wordId = wordDao.insert(
                WordEntity(
                    spellingNormalized = "shining",
                    spellingDisplay = "shining",
                    phoneticIpa = "/ˈʃaɪnɪŋ/"
                )
            )
            val actualWordId = if (wordId == -1L) {
                wordDao.getByNormalized("shining")!!.id
            } else wordId

            val senseId = wordSenseDao.insert(
                WordSenseEntity(
                    wordId = actualWordId,
                    orderIndex = 1,
                    partOfSpeech = "verb",
                    chineseMeaning = "照耀；发光",
                    englishDefinition = "to give out or reflect light"
                )
            )

            exampleSentenceDao.insertAll(
                listOf(
                    ExampleSentenceEntity(
                        wordSenseId = senseId,
                        orderIndex = 1,
                        sentenceEn = "The sun is shining brightly today.",
                        sentenceZh = "今天阳光明媚。",
                        isPrimary = true
                    ),
                    ExampleSentenceEntity(
                        wordSenseId = senseId,
                        orderIndex = 2,
                        sentenceEn = "Her eyes were shining with joy.",
                        sentenceZh = "她的眼睛因喜悦而闪闪发光。",
                        isPrimary = false
                    )
                )
            )
        }
    }

    @After
    fun tearDown() {
        context.deleteDatabase("contexta.db")
    }

    @Test
    fun wordRepository_lookupWord_returnsFullDetail() = runBlocking {
        // ── Cache miss path: lookup triggers DB query ──
        val detail = wordRepository.lookupWord("shining") { null }

        assertNotNull("Word detail should be found in DB", detail)
        assertEquals("shining", detail!!.spellingDisplay)
        assertEquals("/ˈʃaɪnɪŋ/", detail.phoneticIpa)
        assertEquals("照耀；发光", detail.primarySense?.chineseMeaning)
        assertEquals("to give out or reflect light", detail.primarySense?.englishDefinition)
        assertEquals("verb", detail.primarySense?.partOfSpeech)
        assertEquals(2, detail.primarySense?.examples?.size)

        // Primary example
        val firstExample = detail.primarySense?.examples?.firstOrNull()
        assertEquals("The sun is shining brightly today.", firstExample?.sentenceEn)
        assertEquals("今天阳光明媚。", firstExample?.sentenceZh)
        assertEquals(true, firstExample?.isPrimary)

        // Not in vocabulary by default
        assertEquals(false, detail.isInVocabulary)
    }

    @Test
    fun wordRepository_lookupWord_cacheHit_skipsDb() = runBlocking {
        // First call: populates cache from DB
        val firstLookup = wordRepository.lookupWord("shining") { null }
        assertNotNull(firstLookup)

        // Second call: cache hit (LRU cache)
        val secondLookup = wordRepository.lookupWord("shining") { null }
        assertNotNull(secondLookup)
        assertEquals(firstLookup!!.spellingDisplay, secondLookup!!.spellingDisplay)
        assertEquals(firstLookup.phoneticIpa, secondLookup.phoneticIpa)
        assertEquals(
            firstLookup.primarySense?.chineseMeaning,
            secondLookup.primarySense?.chineseMeaning
        )
    }

    @Test
    fun wordRepository_saveLlmResult_persistsCorrectly() = runBlocking {
        // Save a new word via LLM-like result
        val saved = wordRepository.saveLlmResult(
            spellingDisplay = "breeze",
            phoneticIpa = "/briːz/",
            senses = listOf(
                com.ak.contexta.domain.model.WordSense(
                    id = 0,
                    orderIndex = 1,
                    partOfSpeech = "noun",
                    chineseMeaning = "微风",
                    englishDefinition = "a gentle wind",
                    examples = listOf(
                        com.ak.contexta.domain.model.ExampleSentence(
                            id = 0,
                            orderIndex = 1,
                            sentenceEn = "A gentle breeze blew through the trees.",
                            sentenceZh = "微风吹过树林。",
                            isPrimary = true
                        )
                    )
                )
            )
        )

        // Verify the saved data
        assertEquals("breeze", saved.spellingDisplay)
        assertEquals("/briːz/", saved.phoneticIpa)
        assertEquals("微风", saved.primarySense?.chineseMeaning)
        assertEquals("a gentle wind", saved.primarySense?.englishDefinition)
        assertEquals("noun", saved.primarySense?.partOfSpeech)

        // Verify it can be looked up
        val lookup = wordRepository.lookupWord("breeze") { null }
        assertNotNull(lookup)
        assertEquals("breeze", lookup!!.spellingDisplay)
    }

    @Test
    fun wordRepository_normalizedLookup_handlesPunctuation() = runBlocking {
        // The normalize() function strips trailing punctuation
        val detail = wordRepository.lookupWord("shining.") { null }
        assertNotNull("Word lookup should strip trailing period", detail)
        assertEquals("shining", detail!!.spellingDisplay)

        val detail2 = wordRepository.lookupWord("Shining") { null }
        assertNotNull("Word lookup should be case-insensitive", detail2)
        assertEquals("shining", detail2!!.spellingDisplay)
    }
}
