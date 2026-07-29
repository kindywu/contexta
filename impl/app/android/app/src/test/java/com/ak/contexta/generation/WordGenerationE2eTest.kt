package com.ak.contexta.generation

import com.ak.contexta.domain.generation.buildWordLookupSystemPrompt
import com.ak.contexta.domain.generation.buildWordLookupUserPrompt
import com.ak.contexta.domain.generation.parseWordLlmResponse
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.testing.LlmTestClient
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * End-to-end tests for word definition lookup via LLM (no mocking).
 *
 * Tests 5 words spanning different parts of speech and difficulty levels,
 * verifying that the prompts produce parseable XML output from the LLM.
 *
 * Results are saved to build/test-output/words/ for inspection.
 */
class WordGenerationE2eTest {

    private val client = LlmTestClient()
    private val outputDir = File(
        System.getProperty("user.dir"),
        "build/test-output/words"
    ).also { it.mkdirs() }

    /** 5 words spanning different parts of speech and difficulty levels. */
    private val testWords = listOf(
        "resilient",    // adjective
        "phenomenon",   // noun (irregular plural)
        "accommodate",  // verb (commonly misspelled)
        "eloquent",     // adjective
        "serendipity"   // noun (less common)
    )

    @Test(timeout = 300_000)
    fun `look up 5 words via LLM`() = runTest {
        val systemPrompt = buildWordLookupSystemPrompt()

        for ((index, word) in testWords.withIndex()) {
            println("\n--- [$index] Looking up \"$word\" ---")
            val detail = lookupWord(word, systemPrompt)
            saveResult(word, detail)
            println("✓ \"$word\" — ${detail.allSenses.size} sense(s), " +
                "phonetic: ${detail.phoneticIpa ?: "N/A"}")
        }

        println("\n--- All 5 word lookups completed ---")
        println("Results saved to build/test-output/words/")
    }

    private suspend fun lookupWord(
        word: String,
        systemPrompt: String
    ): WordDetail {
        val userPrompt = buildWordLookupUserPrompt(word)

        println("Calling LLM for \"$word\"...")
        val raw = client.call(systemPrompt, userPrompt)
        println("LLM responded (${raw.length} chars)")

        val nullableDetail = parseWordLlmResponse(raw)
        assertNotNull("WordDetail should not be null for '$word'", nullableDetail)
        val detail = nullableDetail!!

        // Spelling check
        assertFalse("spellingDisplay should not be blank", detail.spellingDisplay.isBlank())
        assertTrue(
            "spellingDisplay should match the requested word. " +
                "Expected: '$word', got: '${detail.spellingDisplay}'",
            detail.spellingDisplay.equals(word, ignoreCase = true)
        )

        // Senses
        assertFalse("Should have at least 1 sense for '$word'", detail.allSenses.isEmpty())
        assertTrue(
            "Sense count should be 1-5, got: ${detail.allSenses.size}",
            detail.allSenses.size in 1..5
        )

        detail.allSenses.forEachIndexed { i, sense ->
            assertFalse("Sense ${i + 1} partOfSpeech should not be blank", sense.partOfSpeech.isBlank())
            assertFalse("Sense ${i + 1} chineseMeaning should not be blank", sense.chineseMeaning.isBlank())
            assertFalse("Sense ${i + 1} englishDefinition should not be blank", sense.englishDefinition.isBlank())
            assertTrue("Sense ${i + 1} orderIndex should be ${i + 1}", sense.orderIndex == i + 1)

            // Examples are optional — if present, validate them
            sense.examples.forEachIndexed { exI, ex ->
                assertFalse("Example ${exI + 1} EN should not be blank", ex.sentenceEn.isBlank())
                assertFalse("Example ${exI + 1} ZH should not be blank", ex.sentenceZh.isBlank())
            }
        }

        // primarySense should match first sense
        assertNotNull("primarySense should not be null", detail.primarySense)
        assertTrue("primarySense should be the first sense", detail.primarySense!!.orderIndex == 1)

        // These should be defaults from the parser (no DB IDs)
        assertTrue("wordId should be 0 for parsed-from-response objects", detail.wordId == 0L)
        detail.allSenses.forEach { sense ->
            assertTrue("Each sense id should be 0 for parsed-from-response objects", sense.id == 0L)
            sense.examples.forEach { ex ->
                assertTrue("Each example id should be 0 for parsed-from-response objects", ex.id == 0L)
            }
        }

        // isInVocabulary should default to false
        assertFalse("isInVocabulary should default to false", detail.isInVocabulary)
        assertNull("vocabularyEntryId should default to null", detail.vocabularyEntryId)

        return detail
    }

    private fun saveResult(word: String, detail: WordDetail) {
        val sb = StringBuilder()
        sb.appendLine("==========================================")
        sb.appendLine("Word Lookup Test Result")
        sb.appendLine("==========================================")
        sb.appendLine("Word: $word")
        sb.appendLine("Spelling: ${detail.spellingDisplay}")
        sb.appendLine("Phonetic: ${detail.phoneticIpa ?: "(not provided)"}")
        sb.appendLine("Senses: ${detail.allSenses.size}")
        sb.appendLine()

        detail.allSenses.forEachIndexed { i, sense ->
            sb.appendLine("--- Sense ${i + 1} ---")
            sb.appendLine("  Part of Speech: ${sense.partOfSpeech}")
            sb.appendLine("  Chinese: ${sense.chineseMeaning}")
            sb.appendLine("  English: ${sense.englishDefinition}")

            if (sense.examples.isNotEmpty()) {
                sb.appendLine("  Examples:")
                sense.examples.forEachIndexed { exI, ex ->
                    sb.appendLine("    [${exI + 1} EN] ${ex.sentenceEn}")
                    sb.appendLine("    [${exI + 1} ZH] ${ex.sentenceZh}")
                }
            }
            sb.appendLine()
        }

        File(outputDir, "${word.replace(" ", "_")}.txt").writeText(sb.toString())
    }
}
