package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.AppInfoProvider
import com.ak.contexta.domain.DeveloperAlertSender
import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.error.LlmFatalException
import com.ak.contexta.domain.error.LlmRecoverableExhaustedException
import com.ak.contexta.domain.error.PipelineBlockingException
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

class GenerateArticlesUseCaseTest {

    private val articleRepository: ArticleRepository = mockk()
    private val llmClient: LlmClient = mockk()
    private val timeProvider: TimeProvider = mockk()
    private val appInfo: AppInfoProvider = mockk()
    private val alertSender: DeveloperAlertSender = mockk()

    private lateinit var useCase: GenerateArticlesUseCase

    private val okLlmContent = "<title>Test</title>" +
        "<paragraph>Hello world</paragraph><translation>你好世界</translation>"

    @Before
    fun setUp() {
        useCase = GenerateArticlesUseCase(
            articleRepository = articleRepository,
            llmClient = llmClient,
            timeProvider = timeProvider,
            appInfo = appInfo,
            alertSender = alertSender
        )
        coEvery { timeProvider.nowMillis() } returns 1785636000000L
        coEvery { llmClient.call(any(), any()) } returns LlmClient.LlmResult(okLlmContent, 0)
        coEvery { articleRepository.markErrorNotified(any()) } returns Unit
        coEvery { articleRepository.markBatchReadyNotified(any()) } returns Unit
        coEvery { articleRepository.hasFatalArticle(any()) } returns false
        coEvery { articleRepository.isBatchComplete(any()) } returns false
        // 告警默认发送成功
        coEvery { alertSender.sendArticleFailure(any(), any(), any(), any()) } returns true
        coEvery { alertSender.sendLlmFatalError(any(), any()) } returns true
        coEvery { alertSender.sendStructuralError(any(), any()) } returns true
        coEvery { alertSender.sendBatchReady(any(), any(), any(), any(), any()) } returns true
    }

    private fun article(id: Long, status: ArticleStatus, retryCount: Int = 0): Article {
        val a = mockk<Article>()
        every { a.id } returns id
        every { a.status } returns status
        every { a.retryCount } returns retryCount
        every { a.contentCategory } returns "NEWS"
        every { a.orderIndex } returns id.toInt()
        return a
    }

    // ─── 成功路径 ────────────────────────────────────────────────────────

    @Test
    fun `全部文章成功后批次 READY 并通知飞书 通知送达后回写标记`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(
            article(41, ArticleStatus.PENDING),
            article(42, ArticleStatus.PENDING)
        )
        coEvery { articleRepository.claimArticle(any()) } returns true
        coEvery { articleRepository.completeArticle(any(), any(), any(), any()) } returns Unit
        coEvery { articleRepository.hasFatalArticle(9) } returns false
        coEvery { articleRepository.isBatchComplete(9) } returns true
        coEvery { articleRepository.markBatchReady(9) } returns Unit
        coEvery { articleRepository.getBatchById(9) } returns null

        useCase(9, 1)

        coVerify(exactly = 1) { articleRepository.markBatchReady(9) }
        coVerify(exactly = 1) { alertSender.sendBatchReady(9, 2, null, null, any()) }
        coVerify(exactly = 1) { articleRepository.markBatchReadyNotified(9) }
    }

    @Test
    fun `批次完成通知发送失败时不回写标记 留给启动补发`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(article(41, ArticleStatus.PENDING))
        coEvery { articleRepository.claimArticle(41) } returns true
        coEvery { articleRepository.completeArticle(any(), any(), any(), any()) } returns Unit
        coEvery { articleRepository.hasFatalArticle(9) } returns false
        coEvery { articleRepository.isBatchComplete(9) } returns true
        coEvery { articleRepository.markBatchReady(9) } returns Unit
        coEvery { articleRepository.getBatchById(9) } returns null
        coEvery { alertSender.sendBatchReady(any(), any(), any(), any(), any()) } returns false

        useCase(9, 1)

        coVerify(exactly = 0) { articleRepository.markBatchReadyNotified(9) }
    }

    // ─── 失败路径：错误日志 + 告警 + 送达标记 ───────────────────────────

    @Test
    fun `文章超时后写错误日志 告警送达则回写 notified_at`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(article(42, ArticleStatus.PENDING))
        coEvery { articleRepository.claimArticle(42) } returns true
        coEvery { llmClient.call(any(), any()) } throws RuntimeException("Timed out waiting for 120000 ms")
        coEvery { articleRepository.failArticle(42, "TIMEOUT", "UNEXPECTED", any(), any(), any()) } returns 15L

        useCase(9, 1)

        coVerify(exactly = 1) {
            alertSender.sendArticleFailure("TIMEOUT", "UNEXPECTED", any(), any())
        }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(15) }
    }

    @Test
    fun `告警发送失败时不回写 notified_at 下次启动补发`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(article(42, ArticleStatus.PENDING))
        coEvery { articleRepository.claimArticle(42) } returns true
        coEvery { llmClient.call(any(), any()) } throws RuntimeException("Timed out waiting for 120000 ms")
        coEvery { articleRepository.failArticle(42, "TIMEOUT", "UNEXPECTED", any(), any(), any()) } returns 15L
        coEvery { alertSender.sendArticleFailure(any(), any(), any(), any()) } returns false

        useCase(9, 1)

        coVerify(exactly = 0) { articleRepository.markErrorNotified(15) }
    }

    @Test
    fun `可恢复错误耗尽后文章 FAILED 并发送 FAILED 告警`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(article(24, ArticleStatus.PENDING))
        coEvery { articleRepository.claimArticle(24) } returns true
        coEvery { llmClient.call(any(), any()) } throws LlmRecoverableExhaustedException("LLM call failed after 3 retries")
        coEvery { articleRepository.failArticle(24, "FAILED", "LLM_RECOVERABLE_EXHAUSTED", any(), any(), any()) } returns 14L

        useCase(9, 1)

        coVerify(exactly = 1) {
            alertSender.sendArticleFailure("FAILED", "LLM_RECOVERABLE_EXHAUSTED", any(), any())
        }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(14) }
    }

    @Test
    fun `致命错误发送 LLM Fatal 告警 批次保持 GENERATING 不 READY`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(article(50, ArticleStatus.PENDING))
        coEvery { articleRepository.claimArticle(50) } returns true
        coEvery { llmClient.call(any(), any()) } throws LlmFatalException("auth failed")
        coEvery { articleRepository.fatalArticle(50, "LLM_FATAL", any(), any()) } returns 17L
        coEvery { articleRepository.hasFatalArticle(9) } returns true

        useCase(9, 1)

        coVerify(exactly = 1) { alertSender.sendLlmFatalError(any(), any()) }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(17) }
        coVerify(exactly = 0) { articleRepository.markBatchReady(9) }
    }

    @Test
    fun `结构性错误阻塞管道 发送结构性告警并向上抛出`() = runTest {
        coEvery { articleRepository.getArticles(9) } returns listOf(article(50, ArticleStatus.PENDING))
        coEvery { articleRepository.claimArticle(50) } returns true
        coEvery { llmClient.call(any(), any()) } throws PipelineBlockingException("DB constraint violated")
        coEvery { articleRepository.fatalArticle(50, "PIPELINE_BLOCKING", any(), any()) } returns 18L
        coEvery { articleRepository.markBatchBlocked(9, any(), any()) } returns 19L

        try {
            useCase(9, 1)
            throw AssertionError("expected PipelineBlockingException")
        } catch (e: PipelineBlockingException) {
            // 预期抛出，使 Worker 返回 failure 不重试
        }

        coVerify(exactly = 1) { alertSender.sendStructuralError(any(), any()) }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(18) }
        coVerify(exactly = 1) { articleRepository.markErrorNotified(19) }
    }
}
