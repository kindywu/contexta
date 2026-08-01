package com.ak.contexta.ui.settings

import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.usecase.TriggerNextBatchUseCase
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SettingsViewModelTest {

    private val settingsRepository: SettingsRepository = mockk()
    private val statsRepository: StatsRepository = mockk()
    private val triggerNextBatch: TriggerNextBatchUseCase = mockk()
    private val articleRepository: ArticleRepository = mockk()

    private lateinit var viewModel: SettingsViewModel

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        coEvery { settingsRepository.getSettings() } returns null
        coEvery { statsRepository.getStats() } returns null
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun article(id: Long, title: String?) = Article(
        id = id, batchId = 1L, orderIndex = 0, contentCategory = "science",
        title = title, status = ArticleStatus.SUCCESS,
        generationStartedAt = null, generationCompletedAt = null,
        retryCount = 0, accumulatedReadSeconds = 0, readCompletedAt = null,
        lastRetryAt = null
    )

    @Test
    fun `collects favorited articles into state`() = runTest {
        coEvery { articleRepository.observeFavoritedArticles() } returns flowOf(
            listOf(article(1L, "A"), article(2L, null))
        )
        viewModel = SettingsViewModel(
            settingsRepository, statsRepository, triggerNextBatch, articleRepository
        )
        assertEquals(2, viewModel.state.value.favoritedArticles.size)
        assertEquals("A", viewModel.state.value.favoritedArticles[0].title)
        assertEquals("未命名文章", viewModel.state.value.favoritedArticles[1].title)
        assertFalse(viewModel.state.value.isLoading)
    }

    @Test
    fun `empty favorites list yields empty state list`() = runTest {
        coEvery { articleRepository.observeFavoritedArticles() } returns flowOf(emptyList())
        viewModel = SettingsViewModel(
            settingsRepository, statsRepository, triggerNextBatch, articleRepository
        )
        assertTrue(viewModel.state.value.favoritedArticles.isEmpty())
        assertFalse(viewModel.state.value.isLoading)
    }
}
