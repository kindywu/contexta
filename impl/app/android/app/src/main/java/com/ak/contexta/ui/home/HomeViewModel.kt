package com.ak.contexta.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.BuildConfig
import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.generation.categoryToDifficulty
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.model.DailyLearningInfo
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.usecase.CreateInitialBatchUseCase
import com.ak.contexta.domain.usecase.GetHomeArticlesUseCase
import com.ak.contexta.domain.usecase.StartupOrchestrationUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

data class HomeUiState(
    val dateLabel: String = "",
    val streak: Int = 0,
    val articleGroups: List<ArticleGroupUi> = emptyList(),
    val isLoading: Boolean = true,
    val isGenerating: Boolean = false,
    val generationMessage: String = "",
    val generationErrors: List<ErrorUi> = emptyList()
)

data class ErrorUi(
    val articleId: Long,
    val errorCode: String,
    val errorMessage: String,
    val errorHelp: String,
    val canRetry: Boolean
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
    private val startupOrch: StartupOrchestrationUseCase,
    private val createInitialBatch: CreateInitialBatchUseCase,
    private val getHomeArticles: GetHomeArticlesUseCase,
    private val generationScheduler: BackgroundWorkScheduler
) : ViewModel() {

    private val _state = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = _state.asStateFlow()
    private var observeArticlesJob: Job? = null

    init {
        loadHome()
        observeErrors()
        observeSettingsForRefresh()
    }

    private fun observeErrors() {
        viewModelScope.launch {
            articleRepository.observeGenerationErrors().collect { errors ->
                _state.value = _state.value.copy(
                    generationErrors = errors.map { error ->
                        ErrorUi(
                            articleId = error.entityId,
                            errorCode = error.errorCode,
                            errorMessage = error.errorMessage,
                            errorHelp = error.errorHelp ?: "",
                            canRetry = error.status in listOf("FAILED", "TIMEOUT", "FATAL")
                        )
                    }
                )
            }
        }
    }

    private fun loadHome() {
        viewModelScope.launch {
            // Date label
            val today = LocalDate.now(ZoneId.systemDefault())
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
            val startupResult = startupOrch(appVersion)

            when (startupResult) {
                is StartupOrchestrationUseCase.StartupResult.NeedsInitialBatch -> {
                    _state.value = _state.value.copy(
                        isGenerating = true,
                        generationMessage = "正在准备文章…"
                    )
                    val batchId = createInitialBatch(
                        difficulty = startupResult.difficulty,
                        dailyCount = startupResult.dailyCount
                    )
                    generationScheduler.scheduleBatchGeneration(batchId)
                    observeArticles()
                }
                is StartupOrchestrationUseCase.StartupResult.Ready -> {
                    observeArticles()
                }
                is StartupOrchestrationUseCase.StartupResult.PipelineBlocked -> {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        generationMessage = "生成管道被阻塞，请联系技术支持"
                    )
                }
                is StartupOrchestrationUseCase.StartupResult.NeedsOnboarding -> {
                    _state.value = _state.value.copy(isLoading = false)
                }
            }
        }
    }

    private fun observeSettingsForRefresh() {
        viewModelScope.launch {
            settingsRepository.observeSettings()
                .collect { observeArticles() }
        }
    }

    private fun dateLabelFor(readDate: String): String {
        val zoneId = ZoneId.systemDefault()
        val date = LocalDate.parse(readDate)
        val today = LocalDate.now(zoneId)
        val yesterday = today.minusDays(1)
        return when (date) {
            today -> "今天"
            yesterday -> "昨天"
            else -> "${date.year}年${date.monthValue}月${date.dayOfMonth}日"
        }
    }

    private fun observeArticles() {
        observeArticlesJob?.cancel()
        observeArticlesJob = viewModelScope.launch {
            val historyReads = articleRepository.getAllDailyLearningInfos()

            if (historyReads.isEmpty()) {
                _state.value = _state.value.copy(isLoading = false)
                return@launch
            }

            val allFlows = mutableListOf<Flow<ArticleGroupUi>>()

            for (readInfo in historyReads) {
                val batch = readInfo.batch
                allFlows.add(
                    articleRepository.observeArticles(batch.id)
                        .map { articles ->
                            val settings = settingsRepository.getSettings()
                            val userDifficulty = settings?.difficultyLevel ?: "MEDIUM"
                            val shown = getHomeArticles(articles, userDifficulty, readInfo.dailyCountSnapshot)
                            ArticleGroupUi(
                                dateLabel = dateLabelFor(readInfo.learningDate),
                                articles = shown.map { article ->
                                    ArticleItemUi(
                                        id = article.id,
                                        title = article.title,
                                        description = article.contentCategory,
                                        difficultyLabel = categoryToDifficulty(article.contentCategory),
                                        categoryLabel = article.contentCategory.replace("_", " "),
                                        isReadCompleted = article.readCompletedAt != null
                                    )
                                }
                            )
                        }
                )
            }

            if (allFlows.isEmpty()) {
                _state.value = _state.value.copy(isLoading = false)
                return@launch
            }

            combine(allFlows) { groups ->
                groups.filter { it.articles.isNotEmpty() }
            }.collect { groups ->
                val hasContent = groups.any { it.articles.isNotEmpty() }
                _state.value = _state.value.copy(
                    articleGroups = groups,
                    isLoading = false,
                    isGenerating = !hasContent,
                    generationMessage = if (!hasContent) "当前等级暂无文章" else ""
                )
            }
        }
    }
}
