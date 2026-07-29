package com.ak.contexta.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.BuildConfig
import com.ak.contexta.domain.GenerationManager
import com.ak.contexta.domain.generation.categoryToDifficulty
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.worker.GenerationScheduler
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

data class HomeUiState(
    val greeting: String = "今天",
    val dateLabel: String = "",
    val streak: Int = 0,
    val articleGroups: List<ArticleGroupUi> = emptyList(),
    val isLoading: Boolean = true,
    val isGenerating: Boolean = false,
    val generationMessage: String = ""
)

data class ArticleGroupUi(
    val dateLabel: String,
    val articles: List<ArticleItemUi>
)

data class ArticleItemUi(
    val id: Long,
    val title: String?,
    val description: String,
    val difficultyLabel: String,
    val categoryLabel: String,
    val isReadCompleted: Boolean = false
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val statsRepository: StatsRepository,
    private val generationManager: GenerationManager,
    private val generationScheduler: GenerationScheduler
) : ViewModel() {

    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()

    init {
        loadHome()
    }

    private fun loadHome() {
        viewModelScope.launch {
            // Date greeting
            val today = LocalDate.now(java.time.ZoneId.of("Asia/Shanghai"))
            val dayOfWeek = arrayOf("日", "一", "二", "三", "四", "五", "六")[today.dayOfWeek.value % 7]
            val dateLabel = "${today.year}年${today.monthValue}月${today.dayOfMonth}日 星期$dayOfWeek"

            // Streak
            val stats = statsRepository.getStats()
            val streak = stats?.currentStreak ?: 0

            _state.value = _state.value.copy(
                dateLabel = dateLabel,
                streak = streak
            )

            // Run app startup — check batch state and trigger generation if needed
            val appVersion = BuildConfig.VERSION_CODE
            val startupResult = generationManager.onAppStart(appVersion)

            when (startupResult) {
                is GenerationManager.StartupResult.NeedsInitialBatch -> {
                    _state.value = _state.value.copy(
                        isGenerating = true,
                        generationMessage = "正在准备文章…"
                    )
                    // Create initial batch
                    val batchId = generationManager.startInitialGeneration(
                        difficulty = startupResult.difficulty,
                        dailyCount = startupResult.dailyCount
                    )
                    // Schedule WorkManager to generate the articles via LLM
                    generationScheduler.scheduleBatchGeneration(batchId)
                    // Start observing the batch
                    observeCurrentBatch()
                }
                is GenerationManager.StartupResult.Ready -> {
                    observeCurrentBatch()
                }
                is GenerationManager.StartupResult.WaitingForGeneration -> {
                    _state.value = _state.value.copy(
                        isGenerating = true,
                        generationMessage = "上一批文章已展完，正在生成新文章…"
                    )
                    observeCurrentBatch()
                }
                is GenerationManager.StartupResult.PipelineBlocked -> {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        generationMessage = "生成管道被阻塞，请联系技术支持"
                    )
                }
                is GenerationManager.StartupResult.NeedsOnboarding -> {
                    // Shouldn't reach here — NavGraph handles onboarding first
                    _state.value = _state.value.copy(isLoading = false)
                }
            }
        }
    }

    private suspend fun observeCurrentBatch() {
        val currentBatch = articleRepository.getCurrentBatch()
        if (currentBatch != null) {
            articleRepository.observeArticles(currentBatch.id)
                .map { articles ->
                    val settings = settingsRepository.getSettings()
                    val userDifficulty = settings?.difficultyLevel ?: "MEDIUM"
                    val dailyCount = settings?.dailyArticleCount ?: Int.MAX_VALUE

                    // Filter by user's difficulty level and limit by daily count
                    val shownArticles = articles
                        .filter { it.status != ArticleStatus.PENDING }
                        .filter { categoryToDifficulty(it.contentCategory) == userDifficulty }
                        .sortedBy { it.orderIndex }
                        .take(dailyCount)

                    shownArticles.map { article ->
                        ArticleItemUi(
                            id = article.id,
                            title = article.title,
                            description = article.contentCategory,
                            difficultyLabel = userDifficulty,
                            categoryLabel = article.contentCategory.replace("_", " "),
                            isReadCompleted = article.readCompletedAt != null
                        )
                    }.let { items ->
                        listOf(
                            ArticleGroupUi(
                                dateLabel = _state.value.dateLabel,
                                articles = items
                            )
                        )
                    }
                }
                .collect { groups ->
                    val hasContent = groups.any { it.articles.isNotEmpty() }
                    _state.value = _state.value.copy(
                        articleGroups = groups,
                        isLoading = false,
                        isGenerating = !hasContent,
                        generationMessage = if (!hasContent) "当前等级暂无文章" else ""
                    )
                }
        } else {
            _state.value = _state.value.copy(isLoading = false)
        }
    }
}
