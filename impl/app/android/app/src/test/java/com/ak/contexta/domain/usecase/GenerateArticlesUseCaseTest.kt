package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.AppInfoProvider
import com.ak.contexta.domain.error.LlmFatalException
import com.ak.contexta.domain.error.LlmRecoverableExhaustedException
import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.error.PipelineBlockingException
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test

/**
 * Tests for [GenerateArticlesUseCase].
 * Uses mockk to simulate the full article generation pipeline.
 */
class GenerateArticlesUseCaseTest {

    private val articleRepo = mockk<ArticleRepository>(relaxed = true)
    private val llmClient = mockk<LlmClient>(relaxed = true)
    private val timeProvider = mockk<TimeProvider>(relaxed = true)
    private val appInfo = mockk<AppInfoProvider>(relaxed = true)

    private val useCase = GenerateArticlesUseCase(articleRepo, llmClient, timeProvider, appInfo)

    private val testParagraphs = listOf(
        ArticleParagraph(1, "Hello world", "你好世界"),
        ArticleParagraph(2, "This is a test", "这是一个测试")
    )

    @Before
    fun setup() {
        coEvery { timeProvider.nowMillis() } returns System.currentTimeMillis()
    }

    @Test
    fun `empty articles marks batch ready`() = runTest {
        coEvery { articleRepo.getArticles(1) } returns emptyList()

        useCase(1, null)

        coVerify(exactly = 1) { articleRepo.markBatchReady(1) }
    }

    @Test
    fun `skips already SUCCESS articles`() = runTest {
        val article = Article(
            id = 1, batchId = 1, orderIndex = 1,
            contentCategory = "DAILY_CONVERSATION", title = null,
            status = ArticleStatus.SUCCESS, generationStartedAt = null,
            generationCompletedAt = null, retryCount = 0,
            accumulatedReadSeconds = 0, readCompletedAt = null, lastRetryAt = null
        )
        coEvery { articleRepo.getArticles(1) } returns listOf(article)
        coEvery { articleRepo.isBatchComplete(1) } returns true

        useCase(1, null)

        coVerify(exactly = 0) { articleRepo.claimArticle(any()) }
        coVerify(exactly = 1) { articleRepo.markBatchReady(1) }
    }

    @Test
    fun `generates article successfully`() = runTest {
        val article = Article(
            id = 1, batchId = 1, orderIndex = 1,
            contentCategory = "DAILY_CONVERSATION", title = null,
            status = ArticleStatus.PENDING, generationStartedAt = null,
            generationCompletedAt = null, retryCount = 0,
            accumulatedReadSeconds = 0, readCompletedAt = null, lastRetryAt = null
        )
        coEvery { articleRepo.getArticles(1) } returns listOf(article)
        coEvery { articleRepo.claimArticle(1) } returns true
        coEvery { llmClient.call(any(), any(), any()) } returns LlmClient.LlmResult(
            content = """
                {"title": "Test Title", "paragraphs": [
                    {"english": "Hello", "chinese": "你好"},
                    {"english": "World", "chinese": "世界"}
                ]}
            """.trimIndent(),
            retryCount = 0
        )
        coEvery { articleRepo.isBatchComplete(1) } returns true

        useCase(1, null)

        coVerify(exactly = 1) { articleRepo.completeArticle(1, any(), any(), any()) }
        coVerify(exactly = 1) { articleRepo.markBatchReady(1) }
    }

    @Test
    fun `marks article FATAL on LlmFatalException`() = runTest {
        val article = Article(
            id = 1, batchId = 1, orderIndex = 1,
            contentCategory = "DAILY_CONVERSATION", title = null,
            status = ArticleStatus.PENDING, generationStartedAt = null,
            generationCompletedAt = null, retryCount = 0,
            accumulatedReadSeconds = 0, readCompletedAt = null, lastRetryAt = null
        )
        coEvery { articleRepo.getArticles(1) } returns listOf(article)
        coEvery { articleRepo.claimArticle(1) } returns true
        coEvery { llmClient.call(any(), any(), any()) } throws LlmFatalException("Auth failed")

        useCase(1, null)

        coVerify(exactly = 1) { articleRepo.fatalArticle(1, any(), any()) }
    }

    @Test
    fun `marks article FAILED on recoverable exhausted`() = runTest {
        val article = Article(
            id = 1, batchId = 1, orderIndex = 1,
            contentCategory = "DAILY_CONVERSATION", title = null,
            status = ArticleStatus.PENDING, generationStartedAt = null,
            generationCompletedAt = null, retryCount = 0,
            accumulatedReadSeconds = 0, readCompletedAt = null, lastRetryAt = null
        )
        coEvery { articleRepo.getArticles(1) } returns listOf(article)
        coEvery { articleRepo.claimArticle(1) } returns true
        coEvery { llmClient.call(any(), any(), any()) } throws LlmRecoverableExhaustedException("Rate limit exhausted")

        useCase(1, null)

        coVerify(exactly = 1) { articleRepo.failArticle(1, "FAILED", any(), any(), any()) }
    }

    @Test
    fun `blocks batch on PipelineBlockingException`() = runTest {
        val article = Article(
            id = 1, batchId = 1, orderIndex = 1,
            contentCategory = "DAILY_CONVERSATION", title = null,
            status = ArticleStatus.PENDING, generationStartedAt = null,
            generationCompletedAt = null, retryCount = 0,
            accumulatedReadSeconds = 0, readCompletedAt = null, lastRetryAt = null
        )
        coEvery { articleRepo.getArticles(1) } returns listOf(article)
        coEvery { articleRepo.claimArticle(1) } returns true
        coEvery { llmClient.call(any(), any(), any()) } throws PipelineBlockingException("Parse error")

        try {
            useCase(1, 1)
        } catch (_: PipelineBlockingException) {
            // expected to propagate
        }

        coVerify(exactly = 1) { articleRepo.fatalArticle(1, any(), any()) }
        coVerify(exactly = 1) { articleRepo.markBatchBlocked(1, "Parse error", 1) }
    }

    @Test
    fun `handles unexpected exception gracefully`() = runTest {
        val article = Article(
            id = 1, batchId = 1, orderIndex = 1,
            contentCategory = "DAILY_CONVERSATION", title = null,
            status = ArticleStatus.PENDING, generationStartedAt = null,
            generationCompletedAt = null, retryCount = 0,
            accumulatedReadSeconds = 0, readCompletedAt = null, lastRetryAt = null
        )
        coEvery { articleRepo.getArticles(1) } returns listOf(article)
        coEvery { articleRepo.claimArticle(1) } returns true
        coEvery { llmClient.call(any(), any(), any()) } throws RuntimeException("Unexpected failure")

        useCase(1, null)

        coVerify(exactly = 1) { articleRepo.failArticle(1, "TIMEOUT", any(), any(), any()) }
    }
}
