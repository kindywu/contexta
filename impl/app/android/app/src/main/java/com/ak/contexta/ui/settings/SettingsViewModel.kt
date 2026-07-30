package com.ak.contexta.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.usecase.TriggerNextBatchUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val level: String = "MEDIUM",
    val dailyCount: Int = 3,
    val translationMode: String = "FULL",
    val masteryThreshold: Int = 1,
    val autoPlayAudio: Boolean = false,
    val stats: StatsData = StatsData(),
    val isLoading: Boolean = true
)

data class StatsData(
    val totalArticlesRead: Int = 0,
    val totalWordsAdded: Int = 0,
    val totalWordsMastered: Int = 0,
    val totalLearningDays: Int = 0,
    val currentStreak: Int = 0,
    val longestStreak: Int = 0
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsRepository: SettingsRepository,
    private val statsRepository: StatsRepository,
    private val triggerNextBatch: TriggerNextBatchUseCase
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        loadSettings()
    }

    private fun loadSettings() {
        viewModelScope.launch {
            val settings = settingsRepository.getSettings()
            val stats = statsRepository.getStats()

            if (settings != null) {
                _state.value = SettingsUiState(
                    level = settings.difficultyLevel,
                    dailyCount = settings.dailyArticleCount,
                    translationMode = settings.translationDisplayMode,
                    masteryThreshold = settings.masteryThresholdN,
                    autoPlayAudio = settings.autoPlayAudio,
                    stats = StatsData(
                        totalArticlesRead = stats?.totalArticlesRead ?: 0,
                        totalWordsAdded = stats?.totalWordsAdded ?: 0,
                        totalWordsMastered = stats?.totalWordsMastered ?: 0,
                        totalLearningDays = stats?.totalLearningDays ?: 0,
                        currentStreak = stats?.currentStreak ?: 0,
                        longestStreak = stats?.longestStreak ?: 0
                    ),
                    isLoading = false
                )
            } else {
                _state.value = SettingsUiState(isLoading = false)
            }
        }
    }

    fun updateLevel(level: String) {
        viewModelScope.launch {
            settingsRepository.updateLevel(level)
            _state.value = _state.value.copy(level = level)
            // Trigger generation for new difficulty — triggerNextBatchGeneration
            // skips if a matching batch already exists
            triggerNextBatch(level, _state.value.dailyCount)
        }
    }

    fun incrementDailyCount() {
        viewModelScope.launch {
            val newCount = _state.value.dailyCount + 1
            if (newCount <= 5 && settingsRepository.updateDailyArticleCount(newCount)) {
                _state.value = _state.value.copy(dailyCount = newCount)
            }
        }
    }

    fun decrementDailyCount() {
        viewModelScope.launch {
            val newCount = _state.value.dailyCount - 1
            if (newCount >= 1 && settingsRepository.updateDailyArticleCount(newCount)) {
                _state.value = _state.value.copy(dailyCount = newCount)
            }
        }
    }

    fun updateTranslationMode(mode: String) {
        viewModelScope.launch {
            settingsRepository.updateTranslationMode(mode)
            _state.value = _state.value.copy(translationMode = mode)
        }
    }

    fun incrementMasteryThreshold() {
        viewModelScope.launch {
            val newValue = _state.value.masteryThreshold + 1
            if (newValue <= 5) {
                settingsRepository.updateMasteryThreshold(newValue)
                _state.value = _state.value.copy(masteryThreshold = newValue)
            }
        }
    }

    fun decrementMasteryThreshold() {
        viewModelScope.launch {
            val newValue = _state.value.masteryThreshold - 1
            if (newValue >= 1) {
                settingsRepository.updateMasteryThreshold(newValue)
                _state.value = _state.value.copy(masteryThreshold = newValue)
            }
        }
    }

    fun toggleAutoPlayAudio() {
        viewModelScope.launch {
            val newValue = !_state.value.autoPlayAudio
            settingsRepository.updateAutoPlayAudio(newValue)
            _state.value = _state.value.copy(autoPlayAudio = newValue)
        }
    }
}
