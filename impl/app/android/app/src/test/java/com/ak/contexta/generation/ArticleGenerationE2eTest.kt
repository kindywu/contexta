package com.ak.contexta.generation

import com.ak.contexta.domain.generation.buildArticleSystemPrompt
import com.ak.contexta.domain.generation.buildArticleUserPrompt
import com.ak.contexta.domain.generation.categoryToDifficulty
import com.ak.contexta.domain.generation.parseArticleLlmResponse
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.testing.LlmTestClient
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * End-to-end tests for article generation — directly calls the LLM (no mocking).
 *
 * These tests verify that the prompt builders, LLM, and response parsers
 * work together correctly for each difficulty level, INCLUDING word count
 * constraints based on difficulty:
 *
 *   LOW  (DAILY_CONVERSATION, etc.)  → ≤ 100 English words
 *   MEDIUM (NEWS, etc.)              → 100-300 English words
 *   HIGH  (ACADEMIC_EXCERPT, etc.)   → 300-600 English words
 *
 * A valid DeepSeek API key must be in local.properties.
 * Results are saved to build/test-output/articles/ for inspection.
 */
class ArticleGenerationE2eTest {

    private val client = LlmTestClient()
    private val outputDir = File(
        System.getProperty("user.dir"),
        "build/test-output/articles"
    ).also { it.mkdirs() }

    /**
     * Test article generation at LOW difficulty → DAILY_CONVERSATION category.
     * Expected total English word count: ≤ 100
     */
    @Test(timeout = 180_000)
    fun `generate article for LOW level daily conversation`() = runTest {
        val category = "DAILY_CONVERSATION"
        val difficulty = categoryToDifficulty(category) // → "LOW"
        val orderIndex = 1
        val systemPrompt = buildArticleSystemPrompt(difficulty)
        val userPrompt = buildArticleUserPrompt(category, orderIndex)

        println("--- Calling LLM for $difficulty/$category (this may take up to 2 min) ---")
        val response = client.call(systemPrompt, userPrompt)
        println("--- LLM responded (${response.length} chars) ---")

        val (title, paragraphs) = parseArticleLlmResponse(response)
        val wordCount = totalEnglishWordCount(paragraphs)

        // 1. Title validation
        assertNotNull("Title should not be null", title)
        assertFalse("Title should not be blank", title.isBlank())
        assertTrue("Title should be 2-100 chars, got: '$title'", title.length in 2..100)

        // 2. Paragraph validation (LOW: 4-6 paragraphs)
        assertFalse("Should have at least 1 paragraph", paragraphs.isEmpty())
        assertTrue(
            "LOW paragraph count should be 4-6, got: ${paragraphs.size}",
            paragraphs.size in 4..6
        )

        // 3. LOW word count: > 50 and ≤ 100
        assertTrue(
            "LOW article word count should be > 50, got: $wordCount",
            wordCount > 50
        )
        assertTrue(
            "LOW article word count should be ≤ 100, got: $wordCount",
            wordCount <= 100
        )

        // 4. Each paragraph content
        paragraphs.forEachIndexed { i, p ->
            assertFalse("Paragraph ${i + 1} English should not be blank", p.englishText.isBlank())
            assertFalse("Paragraph ${i + 1} Chinese translation should not be blank", p.chineseTranslation.isBlank())
            assertTrue("Paragraph ${i + 1} English too short: '${p.englishText}'", p.englishText.length >= 10)
            assertTrue("Paragraph ${i + 1} orderIndex should be ${i + 1}", p.orderIndex == i + 1)
        }

        // Print word count for visibility
        println("ℹ LOW word count: $wordCount (50 < LOW ≤ 100)")

        // Save result
        saveResult("low_daily_conversation", difficulty, category, title, paragraphs, wordCount, response)
        println("✓ $difficulty/$category — Title: \"$title\", ${paragraphs.size} paragraphs, $wordCount words")
    }

    /**
     * Test article generation at MEDIUM difficulty → NEWS category.
     * Expected total English word count: 100-300
     */
    @Test(timeout = 180_000)
    fun `generate article for MEDIUM level news`() = runTest {
        val category = "NEWS"
        val difficulty = categoryToDifficulty(category) // → "MEDIUM"
        val orderIndex = 1
        val systemPrompt = buildArticleSystemPrompt(difficulty)
        val userPrompt = buildArticleUserPrompt(category, orderIndex)

        println("--- Calling LLM for $difficulty/$category ---")
        val response = client.call(systemPrompt, userPrompt)
        println("--- LLM responded (${response.length} chars) ---")

        val (title, paragraphs) = parseArticleLlmResponse(response)
        val wordCount = totalEnglishWordCount(paragraphs)

        assertNotNull("Title should not be null", title)
        assertFalse("Title should not be blank", title.isBlank())
        assertTrue("Title should be 2-100 chars, got: '$title'", title.length in 2..100)

        assertFalse("Should have at least 1 paragraph", paragraphs.isEmpty())
        assertTrue(
            "MEDIUM paragraph count should be 5-7, got: ${paragraphs.size}",
            paragraphs.size in 5..7
        )

        // MEDIUM word count: > 100 and ≤ 300
        assertTrue(
            "MEDIUM article word count should be > 100, got: $wordCount",
            wordCount > 100
        )
        assertTrue(
            "MEDIUM article word count should be ≤ 300, got: $wordCount",
            wordCount <= 300
        )

        paragraphs.forEachIndexed { i, p ->
            assertFalse("Paragraph ${i + 1} English should not be blank", p.englishText.isBlank())
            assertFalse("Paragraph ${i + 1} Chinese translation should not be blank", p.chineseTranslation.isBlank())
            assertTrue("Paragraph ${i + 1} English too short", p.englishText.length >= 10)
            assertTrue("Paragraph ${i + 1} orderIndex mismatch", p.orderIndex == i + 1)
        }

        println("ℹ MEDIUM word count: $wordCount (100 < MEDIUM ≤ 300)")

        saveResult("medium_news", difficulty, category, title, paragraphs, wordCount, response)
        println("✓ $difficulty/$category — Title: \"$title\", ${paragraphs.size} paragraphs, $wordCount words")
    }

    /**
     * Test article generation at HIGH difficulty → ACADEMIC_EXCERPT category.
     * Expected total English word count: > 300 and ≤ 600
     */
    @Test(timeout = 180_000)
    fun `generate article for HIGH level academic excerpt`() = runTest {
        val category = "ACADEMIC_EXCERPT"
        val difficulty = categoryToDifficulty(category) // → "HIGH"
        val orderIndex = 1
        val systemPrompt = buildArticleSystemPrompt(difficulty)
        val userPrompt = buildArticleUserPrompt(category, orderIndex)

        println("--- Calling LLM for $difficulty/$category ---")
        val response = client.call(systemPrompt, userPrompt)
        println("--- LLM responded (${response.length} chars) ---")

        val (title, paragraphs) = parseArticleLlmResponse(response)
        val wordCount = totalEnglishWordCount(paragraphs)

        assertNotNull("Title should not be null", title)
        assertFalse("Title should not be blank", title.isBlank())
        assertTrue("Title should be 2-100 chars, got: '$title'", title.length in 2..100)

        assertFalse("Should have at least 1 paragraph", paragraphs.isEmpty())
        assertTrue(
            "HIGH paragraph count should be 8-12, got: ${paragraphs.size}",
            paragraphs.size in 8..12
        )

        // HIGH word count: > 300 and ≤ 600
        assertTrue(
            "HIGH article word count should be > 300, got: $wordCount",
            wordCount > 300
        )
        assertTrue(
            "HIGH article word count should be ≤ 600, got: $wordCount",
            wordCount <= 600
        )

        paragraphs.forEachIndexed { i, p ->
            assertFalse("Paragraph ${i + 1} English should not be blank", p.englishText.isBlank())
            assertFalse("Paragraph ${i + 1} Chinese translation should not be blank", p.chineseTranslation.isBlank())
            assertTrue("Paragraph ${i + 1} English too short", p.englishText.length >= 10)
            assertTrue("Paragraph ${i + 1} orderIndex mismatch", p.orderIndex == i + 1)
        }

        println("ℹ HIGH word count: $wordCount (300 < HIGH ≤ 600 expected)")

        saveResult("high_academic_excerpt", difficulty, category, title, paragraphs, wordCount, response)
        println("✓ $difficulty/$category — Title: \"$title\", ${paragraphs.size} paragraphs, $wordCount words")
    }

    // ---- word count helpers ----

    /** Total English word count across all paragraphs. */
    private fun totalEnglishWordCount(paragraphs: List<ArticleParagraph>): Int =
        paragraphs.sumOf { p -> p.englishText.split("\\s+".toRegex()).count { it.isNotBlank() } }

    // ---- output helpers ----

    private fun saveResult(
        slug: String,
        difficulty: String,
        category: String,
        title: String,
        paragraphs: List<ArticleParagraph>,
        wordCount: Int,
        rawResponse: String
    ) {
        val sb = StringBuilder()
        sb.appendLine("==========================================")
        sb.appendLine("Article Generation Test Result")
        sb.appendLine("==========================================")
        sb.appendLine("Difficulty: $difficulty")
        sb.appendLine("Category: $category")
        sb.appendLine("Title: $title")
        sb.appendLine("Paragraph count: ${paragraphs.size}")
        sb.appendLine("Total English words: $wordCount")
        sb.appendLine()
        sb.appendLine("--- Parsed Content ---")
        paragraphs.forEachIndexed { i, p ->
            sb.appendLine("[${i + 1} EN] ${p.englishText}")
            sb.appendLine("[${i + 1} ZH] ${p.chineseTranslation}")
            sb.appendLine()
        }
        sb.appendLine("--- Raw LLM Response ---")
        sb.appendLine(rawResponse)
        sb.appendLine("--- END ---")

        File(outputDir, "$slug.txt").writeText(sb.toString())
        println("Result saved to build/test-output/articles/$slug.txt")
    }
}
