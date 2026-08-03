package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.model.ArticleBatch
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.UserSettings
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.time.TimeProvider
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class StartupOrchestrationUseCaseTest {

    private val articleRepository: ArticleRepository = mockk()
    private val settingsRepository: SettingsRepository = mockk()
    private val timeProvider: TimeProvider = mockk()
    private val triggerNextBatch: TriggerNextBatchUseCase = mockk()
    private val generationScheduler: BackgroundWorkScheduler = mockk()
    private val resendPendingAlerts: ResendPendingAlertsUseCase = mockk()

    private lateinit var useCase: StartupOrchestrationUseCase

    private val settings = UserSettings(
        isOnboarded = true,
        difficultyLevel = "LOW",
        dailyArticleCount = 5
    )

    @Before
    fun setUp() {
        useCase = StartupOrchestrationUseCase(
            articleRepository = articleRepository,
            settingsRepository = settingsRepository,
            timeProvider = timeProvider,
            triggerNextBatch = triggerNextBatch,
            generationScheduler = generationScheduler,
            resendPendingAlerts = resendPendingAlerts
        )
        coEvery { settingsRepository.getSettings() } returns settings
        coEvery { timeProvider.todayDateString() } returns "2026-08-01"
        coEvery { articleRepository.isPipelineBlocked() } returns false
        coEvery { articleRepository.getGeneratingBatches() } returns emptyList()
        coEvery { articleRepository.reconcileOrphanArticles() } returns Unit
        coEvery { triggerNextBatch.invoke(any(), any()) } returns Unit
        coEvery { generationScheduler.scheduleBatchGeneration(any(), any()) } returns true
        coEvery { resendPendingAlerts.invoke() } returns Unit
    }

    // ─── 修复核心：分配批次时传 maxRefDate，不回头选旧 seed 批次 ───────────

    @Test
    fun `未分配时 findNextReadyBatch 收到 maxRefDate 而不是 null`() = runTest {
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns null
        coEvery { articleRepository.getMaxRefBatchDate() } returns "2026-03-29"
        coEvery { articleRepository.findNextReadyBatch(any(), any()) } returns null

        useCase(currentVersionCode = 1)

        // 关键断言：afterDate 必须是 maxRefDate（严格晚于已消费批次），否则会回头选 seed 旧批次
        coVerify(exactly = 1) {
            articleRepository.findNextReadyBatch(difficulty = "LOW", afterDate = "2026-03-29")
        }
    }

    @Test
    fun `maxRefDate 之后有 READY 批次时分配给今天并触发前置生成`() = runTest {
        val nextBatch = ArticleBatch(
            id = 6,
            status = BatchStatus.READY,
            difficultyLevelSnapshot = "LOW",
            generatedOn = "2026-07-31",
            lastUpdatedAt = "2026-07-31T21:25:42+08:00"
        )
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns null
        coEvery { articleRepository.getMaxRefBatchDate() } returns "2026-03-29"
        coEvery { articleRepository.findNextReadyBatch("LOW", "2026-03-29") } returns nextBatch
        coEvery { articleRepository.assignBatchForToday(6, "2026-07-31", 5) } returns true

        val result = useCase(currentVersionCode = 1)

        assertEquals(StartupOrchestrationUseCase.StartupResult.Ready, result)
        coVerify(exactly = 1) {
            articleRepository.assignBatchForToday(batchId = 6, refBatchDate = "2026-07-31", dailyCount = 5)
        }
        coVerify(exactly = 1) { triggerNextBatch.invoke("LOW", 5) }
    }

    @Test
    fun `今天已分配时只触发前置生成 不重新查找批次`() = runTest {
        val todayBatch = ArticleBatch(
            id = 1,
            status = BatchStatus.READY,
            difficultyLevelSnapshot = "LOW",
            generatedOn = "2026-03-29",
            lastUpdatedAt = "2026-03-29T12:00:00+08:00"
        )
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns todayBatch

        val result = useCase(currentVersionCode = 1)

        assertEquals(StartupOrchestrationUseCase.StartupResult.Ready, result)
        coVerify(exactly = 1) { triggerNextBatch.invoke("LOW", 5) }
        coVerify(exactly = 0) { articleRepository.findNextReadyBatch(any(), any()) }
    }

    // ─── 无可用批次 → NeedsInitialBatch ─────────────────────────────────

    @Test
    fun `maxRefDate 之后无 READY 批次时返回 NeedsInitialBatch`() = runTest {
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns null
        coEvery { articleRepository.getMaxRefBatchDate() } returns "2026-07-31"
        coEvery { articleRepository.findNextReadyBatch("LOW", "2026-07-31") } returns null

        val result = useCase(currentVersionCode = 1)

        assertEquals(
            StartupOrchestrationUseCase.StartupResult.NeedsInitialBatch(
                difficulty = "LOW",
                dailyCount = 5
            ),
            result
        )
        coVerify(exactly = 0) { triggerNextBatch.invoke(any(), any()) }
    }

    // ─── 卡死批次重新调度 ───────────────────────────────────────────────

    @Test
    fun `GENERATING 批次在 reconcile 后被重新调度`() = runTest {
        val stuck = ArticleBatch(
            id = 6,
            status = BatchStatus.GENERATING,
            difficultyLevelSnapshot = "LOW",
            generatedOn = "2026-07-31",
            lastUpdatedAt = "2026-07-31T21:25:29+08:00"
        )
        coEvery { articleRepository.getGeneratingBatches() } returns listOf(stuck)
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns null
        coEvery { articleRepository.getMaxRefBatchDate() } returns "2026-07-31"
        coEvery { articleRepository.findNextReadyBatch("LOW", "2026-07-31") } returns null

        useCase(currentVersionCode = 1)

        coVerify(exactly = 1) { generationScheduler.scheduleBatchGeneration(6) }
    }

    // ─── 未送达告警补发 ─────────────────────────────────────────────────

    @Test
    fun `启动时补发未送达的飞书告警`() = runTest {
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns null
        coEvery { articleRepository.getMaxRefBatchDate() } returns "2026-07-31"
        coEvery { articleRepository.findNextReadyBatch("LOW", "2026-07-31") } returns null

        useCase(currentVersionCode = 1)

        coVerify(exactly = 1) { resendPendingAlerts.invoke() }
    }

    @Test
    fun `补发告警失败不影响启动主流程`() = runTest {
        coEvery { resendPendingAlerts.invoke() } throws RuntimeException("webhook down")
        coEvery { articleRepository.getAssignedBatchForDate("2026-08-01") } returns null
        coEvery { articleRepository.getMaxRefBatchDate() } returns "2026-07-31"
        coEvery { articleRepository.findNextReadyBatch("LOW", "2026-07-31") } returns null

        val result = useCase(currentVersionCode = 1)

        // 补发失败被 runCatching 吞掉，启动编排照常完成
        assertEquals(
            StartupOrchestrationUseCase.StartupResult.NeedsInitialBatch("LOW", 5),
            result
        )
    }

    // ─── 管道阻塞 ────────────────────────────────────────────────────────

    @Test
    fun `管道阻塞且版本未更新时返回 PipelineBlocked`() = runTest {
        coEvery { articleRepository.isPipelineBlocked() } returns true
        coEvery { articleRepository.recoverIfNewerVersion(1) } returns false

        val result = useCase(currentVersionCode = 1)

        assertTrue(result is StartupOrchestrationUseCase.StartupResult.PipelineBlocked)
    }
}
