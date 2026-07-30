package com.ak.contexta.domain.usecase

import com.ak.contexta.domain.model.ArticleBatch
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.BatchType
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.model.UserSettings
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.time.TimeProvider
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for [StartupOrchestrationUseCase].
 * Uses mockk for repository dependencies.
 */
class StartupOrchestrationUseCaseTest {

    private val articleRepo = mockk<ArticleRepository>(relaxed = true)
    private val settingsRepo = mockk<SettingsRepository>(relaxed = true)
    private val triggerNextBatch = mockk<TriggerNextBatchUseCase>(relaxed = true)
    private val timeProvider = mockk<TimeProvider>(relaxed = true)

    private val useCase = StartupOrchestrationUseCase(
        articleRepo, settingsRepo, triggerNextBatch, timeProvider
    )

    private fun settings() = UserSettings(
        id = 1,
        isOnboarded = true,
        difficultyLevel = "MEDIUM",
        dailyArticleCount = 3,
        translationDisplayMode = "FULL",
        masteryThresholdN = 1,
        autoPlayAudio = false
    )

    @Test
    fun `returns NeedsOnboarding when settings is null`() = runTest {
        coEvery { settingsRepo.getSettings() } returns null
        coEvery { articleRepo.isPipelineBlocked() } returns false

        val result = useCase(1)
        assertTrue(result is StartupOrchestrationUseCase.StartupResult.NeedsOnboarding)
    }

    @Test
    fun `returns NeedsOnboarding when not onboarded`() = runTest {
        coEvery { settingsRepo.getSettings() } returns settings().copy(isOnboarded = false)
        coEvery { articleRepo.isPipelineBlocked() } returns false

        val result = useCase(1)
        assertTrue(result is StartupOrchestrationUseCase.StartupResult.NeedsOnboarding)
    }

    @Test
    fun `returns PipelineBlocked when blocked and recovery fails`() = runTest {
        coEvery { settingsRepo.getSettings() } returns settings()
        coEvery { articleRepo.isPipelineBlocked() } returns true
        coEvery { articleRepo.recoverIfNewerVersion(any()) } returns false

        val result = useCase(1)
        assertTrue(result is StartupOrchestrationUseCase.StartupResult.PipelineBlocked)
    }

    @Test
    fun `returns NeedsInitialBatch when no batches exist`() = runTest {
        coEvery { settingsRepo.getSettings() } returns settings()
        coEvery { articleRepo.isPipelineBlocked() } returns false
        coEvery { articleRepo.getCurrentBatch() } returns null
        coEvery { articleRepo.getNextBatch() } returns null
        coEvery { timeProvider.todayDateString() } returns "2026-07-30"

        val result = useCase(1)
        assertTrue(result is StartupOrchestrationUseCase.StartupResult.NeedsInitialBatch)
        val needs = result as StartupOrchestrationUseCase.StartupResult.NeedsInitialBatch
        assertEquals("MEDIUM", needs.difficulty)
        assertEquals(3, needs.dailyCount)
    }

    @Test
    fun `returns Ready when current batch exists`() = runTest {
        coEvery { settingsRepo.getSettings() } returns settings()
        coEvery { articleRepo.isPipelineBlocked() } returns false
        coEvery { articleRepo.getCurrentBatch() } returns ArticleBatch(
            id = 1, batchType = BatchType.CURRENT, status = BatchStatus.CURRENT,
            difficultyLevelSnapshot = "MEDIUM", dailyCountSnapshot = 3,
            generatedOn = "2026-07-29", unlockedOn = "2026-07-29", lastUpdatedAt = 0
        )
        coEvery { articleRepo.getNextBatch() } returns null
        coEvery { timeProvider.todayDateString() } returns "2026-07-30"

        val result = useCase(1)
        assertTrue(result is StartupOrchestrationUseCase.StartupResult.Ready)
    }

    @Test
    fun `promotes next to current when next day and next is READY`() = runTest {
        coEvery { settingsRepo.getSettings() } returns settings()
        coEvery { articleRepo.isPipelineBlocked() } returns false
        coEvery { articleRepo.getCurrentBatch() } returns ArticleBatch(
            id = 1, batchType = BatchType.CURRENT, status = BatchStatus.CURRENT,
            difficultyLevelSnapshot = "MEDIUM", dailyCountSnapshot = 3,
            generatedOn = "2026-07-29", unlockedOn = "2026-07-29", lastUpdatedAt = 0
        )
        coEvery { articleRepo.getNextBatch() } returns ArticleBatch(
            id = 2, batchType = BatchType.NEXT, status = BatchStatus.READY,
            difficultyLevelSnapshot = "MEDIUM", dailyCountSnapshot = 3,
            generatedOn = "2026-07-29", unlockedOn = null, lastUpdatedAt = 0
        )
        coEvery { timeProvider.todayDateString() } returns "2026-07-30"

        val result = useCase(1)
        assertTrue(result is StartupOrchestrationUseCase.StartupResult.Ready)
        coVerify(exactly = 1) { articleRepo.promoteNextToCurrent(2) }
        coVerify(exactly = 1) { triggerNextBatch("MEDIUM", 3) }
    }
}
