package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.AppInfoProvider
import com.ak.contexta.domain.DeveloperAlertSender
import com.ak.contexta.domain.model.ArticleBatch
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.GenerationError
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class ResendPendingAlertsUseCaseTest {

    private val articleRepository: ArticleRepository = mockk()
    private val alertSender: DeveloperAlertSender = mockk()
    private val timeProvider: TimeProvider = mockk()
    private val appInfo: AppInfoProvider = mockk()

    private lateinit var useCase: ResendPendingAlertsUseCase

    @Before
    fun setUp() {
        useCase = ResendPendingAlertsUseCase(
            articleRepository = articleRepository,
            alertSender = alertSender,
            timeProvider = timeProvider,
            appInfo = appInfo
        )
        coEvery { timeProvider.nowMillis() } returns 1785636000000L
        coEvery { appInfo.versionCode } returns 1
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns emptyList()
        coEvery { articleRepository.getReadyBatchesUnnotified() } returns emptyList()
        coEvery { articleRepository.markErrorNotified(any()) } returns Unit
        coEvery { articleRepository.markBatchReadyNotified(any()) } returns Unit
        // 告警默认发送成功
        coEvery { alertSender.sendArticleFailure(any(), any(), any(), any()) } returns true
        coEvery { alertSender.sendBatchReady(any(), any(), any(), any(), any()) } returns true
        coEvery { alertSender.sendLlmFatalError(any(), any()) } returns true
        coEvery { alertSender.sendStructuralError(any(), any()) } returns true
    }

    @Test
    fun `没有未通知的错误和批次时 不发送任何告警`() = runTest {
        useCase()

        coVerify(exactly = 0) { alertSender.sendArticleFailure(any(), any(), any(), any()) }
        coVerify(exactly = 0) { alertSender.sendBatchReady(any(), any(), any(), any(), any()) }
    }

    @Test
    fun `未通知的 ARTICLE 错误 补发 TIMEOUT 告警并回写标记`() = runTest {
        val error = GenerationError(
            id = 15,
            entityId = 42,
            entityType = "ARTICLE",
            errorCode = "UNEXPECTED",
            errorMessage = "Timed out waiting for 120000 ms",
            errorHelp = null,
            retryCount = 0,
            createdAt = "2026-08-02T09:34:29+08:00"
        )
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns listOf(error)
        coEvery { articleRepository.getArticle(42) } returns null

        useCase()

        coVerify(exactly = 1) {
            alertSender.sendArticleFailure(
                status = "TIMEOUT",
                errorCode = "UNEXPECTED",
                errorMessage = "Timed out waiting for 120000 ms",
                context = match { it.articleId == 42L && it.batchId == null }
            )
        }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(15) }
    }

    @Test
    fun `LLM_RECOVERABLE_EXHAUSTED 错误补发 FAILED 告警`() = runTest {
        val error = GenerationError(
            id = 14,
            entityId = 24,
            entityType = "ARTICLE",
            errorCode = "LLM_RECOVERABLE_EXHAUSTED",
            errorMessage = "LLM call failed after 3 retries",
            errorHelp = null,
            retryCount = 0,
            createdAt = "2026-07-31T21:19:13+08:00"
        )
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns listOf(error)
        coEvery { articleRepository.getArticle(24) } returns null

        useCase()

        coVerify(exactly = 1) {
            alertSender.sendArticleFailure(status = "FAILED", errorCode = "LLM_RECOVERABLE_EXHAUSTED", any(), any())
        }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(14) }
    }

    @Test
    fun `BATCH 类型错误补发结构性告警 并携带 batchId 上下文`() = runTest {
        val error = GenerationError(
            id = 16,
            entityId = 9,
            entityType = "BATCH",
            errorCode = "STRUCTURAL_PIPELINE_BLOCKED",
            errorMessage = "pipeline blocked",
            errorHelp = null,
            retryCount = 0,
            createdAt = "2026-08-02T09:35:00+08:00"
        )
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns listOf(error)

        useCase()

        coVerify(exactly = 1) {
            alertSender.sendStructuralError(
                any(),
                match { it.batchId == 9L && it.articleId == null }
            )
        }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(16) }
    }

    @Test
    fun `未通知的 READY 批次补发完成告警并回写标记`() = runTest {
        val batch = ArticleBatch(
            id = 9,
            status = BatchStatus.READY,
            difficultyLevelSnapshot = "HIGH",
            generatedOn = "2026-08-02",
            lastUpdatedAt = "2026-08-02T10:05:03+08:00"
        )
        coEvery { articleRepository.getReadyBatchesUnnotified() } returns listOf(batch)
        coEvery { articleRepository.getArticles(9) } returns List(5) { mockk() }

        useCase()

        coVerify(exactly = 1) {
            alertSender.sendBatchReady(
                batchId = 9,
                articleCount = 5,
                batchGeneratedOn = "2026-08-02",
                batchDifficulty = "HIGH",
                any()
            )
        }
        coVerify(exactly = 1) { articleRepository.markBatchReadyNotified(9) }
    }

    @Test
    fun `告警发送失败时不回写标记 下次启动继续补发`() = runTest {
        val error = GenerationError(
            id = 15,
            entityId = 42,
            entityType = "ARTICLE",
            errorCode = "UNEXPECTED",
            errorMessage = "Timed out",
            errorHelp = null,
            retryCount = 0,
            createdAt = "2026-08-02T09:34:29+08:00"
        )
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns listOf(error)
        coEvery { articleRepository.getArticle(42) } returns null
        coEvery { alertSender.sendArticleFailure(any(), any(), any(), any()) } returns false

        useCase()

        coVerify(exactly = 0) { articleRepository.markErrorNotified(15) }
    }

    @Test
    fun `LLM_FATAL 错误补发致命告警`() = runTest {
        val error = GenerationError(
            id = 17,
            entityId = 50,
            entityType = "ARTICLE",
            errorCode = "LLM_FATAL",
            errorMessage = "auth failed",
            errorHelp = null,
            retryCount = 0,
            createdAt = "2026-08-02T10:00:00+08:00"
        )
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns listOf(error)
        coEvery { articleRepository.getArticle(50) } returns null

        useCase()

        coVerify(exactly = 1) { alertSender.sendLlmFatalError(any(), any()) }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(17) }
    }

    @Test
    fun `ARTICLE 错误带出所属批次的 batchId`() = runTest {
        val error = GenerationError(
            id = 18,
            entityId = 42,
            entityType = "ARTICLE",
            errorCode = "UNEXPECTED",
            errorMessage = "Timed out",
            errorHelp = null,
            retryCount = 0,
            createdAt = "2026-08-02T09:34:29+08:00"
        )
        coEvery { articleRepository.getUnnotifiedErrors(any()) } returns listOf(error)
        val article = mockk<com.ak.contexta.domain.model.Article>()
        coEvery { article.batchId } returns 9L
        coEvery { articleRepository.getArticle(42) } returns article

        useCase()

        coVerify(exactly = 1) {
            alertSender.sendArticleFailure(any(), any(), any(), match { it.batchId == 9L })
        }
    }
}
