package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleStatus
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Tests for [GetHomeArticlesUseCase] — pure domain filtering/sorting logic.
 * No dependencies, no coroutines, no mocking needed.
 */
class GetHomeArticlesUseCaseTest {

    private val useCase = GetHomeArticlesUseCase()

    private fun article(
        id: Long,
        orderIndex: Int,
        contentCategory: String,
        status: ArticleStatus = ArticleStatus.SUCCESS
    ) = Article(
        id = id,
        batchId = 1,
        orderIndex = orderIndex,
        contentCategory = contentCategory,
        title = "Article $id",
        status = status,
        generationStartedAt = null,
        generationCompletedAt = null,
        retryCount = 0,
        accumulatedReadSeconds = 0,
        readCompletedAt = null,
        lastRetryAt = null
    )

    @Test
    fun `returns matching difficulty articles sorted by orderIndex`() {
        val articles = listOf(
            article(1, 3, "DAILY_CONVERSATION"), // LOW
            article(2, 1, "DAILY_CONVERSATION"), // LOW
            article(3, 2, "NEWS"),               // MEDIUM
        )
        val result = useCase(articles, "LOW", 10)
        assertEquals(2, result.size)
        assertEquals(1, result[0].orderIndex) // sorted
        assertEquals(3, result[1].orderIndex)
        assertEquals("DAILY_CONVERSATION", result[0].contentCategory)
        assertEquals("DAILY_CONVERSATION", result[1].contentCategory)
    }

    @Test
    fun `returns fallback articles when no matching difficulty`() {
        val articles = listOf(
            article(1, 1, "DAILY_CONVERSATION"), // LOW
            article(2, 2, "NEWS"),               // MEDIUM
        )
        val result = useCase(articles, "HIGH", 10)
        assertEquals(2, result.size) // fallback: all non-PENDING
    }

    @Test
    fun `excludes PENDING articles`() {
        val articles = listOf(
            article(1, 1, "DAILY_CONVERSATION", ArticleStatus.PENDING),
            article(2, 2, "DAILY_CONVERSATION", ArticleStatus.SUCCESS),
            article(3, 3, "DAILY_CONVERSATION", ArticleStatus.GENERATING),
        )
        val result = useCase(articles, "LOW", 10)
        assertEquals(2, result.size)
        assert(result.none { it.status == ArticleStatus.PENDING })
    }

    @Test
    fun `respects display limit`() {
        val articles = (1..10).map { article(it.toLong(), it, "DAILY_CONVERSATION") }
        val result = useCase(articles, "LOW", 3)
        assertEquals(3, result.size)
    }

    @Test
    fun `empty list returns empty`() {
        val result = useCase(emptyList(), "LOW", 10)
        assertEquals(0, result.size)
    }

    @Test
    fun `all pending returns empty`() {
        val articles = listOf(
            article(1, 1, "DAILY_CONVERSATION", ArticleStatus.PENDING),
            article(2, 2, "NEWS", ArticleStatus.PENDING),
        )
        val result = useCase(articles, "LOW", 10)
        assertEquals(0, result.size)
    }
}
