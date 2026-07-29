package com.ak.contexta.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import javax.inject.Inject

data class HomeUiState(
    val greeting: String = "今天",
    val dateLabel: String = "",
    val streak: Int = 0,
    val selectedFilter: String = "全部",
    val articleGroups: List<ArticleGroupUi> = emptyList(),
    val isLoading: Boolean = true
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
    val categoryLabel: String
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val statsRepository: StatsRepository
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
                streak = streak,
                isLoading = false
            )

            // Observe articles from current batch
            val currentBatch = articleRepository.getCurrentBatch()
            if (currentBatch != null) {
                articleRepository.observeArticles(currentBatch.id)
                    .map { articles ->
                        val settings = settingsRepository.getSettings()
                        val selectedLevel = _state.value.selectedFilter

                        val filtered = if (selectedLevel == "全部") {
                            articles
                        } else {
                            val levelCode = when (selectedLevel) {
                                "初级" -> "LOW"
                                "中级" -> "MEDIUM"
                                "高级" -> "HIGH"
                                else -> null
                            }
                            articles
                        }

                        // Group by date (using generatedOn from batch for simplicity)
                        filtered.map { article ->
                            ArticleItemUi(
                                id = article.id,
                                title = article.title,
                                description = article.contentCategory,
                                difficultyLabel = settings?.difficultyLevel ?: "MEDIUM",
                                categoryLabel = article.contentCategory.replace("_", " ")
                            )
                        }.let { items ->
                            listOf(
                                ArticleGroupUi(
                                    dateLabel = dateLabel,
                                    articles = items
                                )
                            )
                        }
                    }
                    .collect { groups ->
                        _state.value = _state.value.copy(articleGroups = groups)
                    }
            }
        }
    }

    fun setFilter(filter: String) {
        _state.value = _state.value.copy(selectedFilter = filter)
        loadHome()
    }
}
