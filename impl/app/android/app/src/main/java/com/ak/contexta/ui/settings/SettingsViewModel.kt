package com.ak.contexta.ui.settings

import android.util.Log
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
    val isLoading: Boolean = true,
    // Info tip dialogs (click ℹ️ icon)
    val showLevelInfoDialog: Boolean = false,
    val showCountInfoDialog: Boolean = false,
    // Confirmation dialogs (setting takes effect tomorrow)
    val showLevelConfirmDialog: Boolean = false,
    val showCountConfirmDialog: Boolean = false,
    val pendingLevel: String? = null,       //暂存待确认的难度
    val pendingCount: Int? = null            //暂存待确认的篇数
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

    // ── ℹ️ Info dialogs ──

    fun showLevelInfo() {
        _state.value = _state.value.copy(showLevelInfoDialog = true)
    }

    fun showCountInfo() {
        _state.value = _state.value.copy(showCountInfoDialog = true)
    }

    fun dismissInfoDialog() {
        _state.value = _state.value.copy(
            showLevelInfoDialog = false,
            showCountInfoDialog = false
        )
    }

    // ── Level change: request → confirm → persist + trigger generation ──

    /** 用户选择新难度后调用：暂存并弹出确认弹窗。 */
    fun requestLevelChange(level: String) {
        if (level == _state.value.level) {
            Log.d("SettingsVM", "requestLevelChange: $level == current, ignored")
            return // 未变更
        }
        Log.d("SettingsVM", "requestLevelChange: $level, pendingLevel=$level, showConfirmDialog")
        _state.value = _state.value.copy(
            pendingLevel = level,
            showLevelConfirmDialog = true
        )
    }

    /** 用户确认修改难度。 */
    fun confirmLevelChange() {
        val level = _state.value.pendingLevel
        Log.d("SettingsVM", "confirmLevelChange: pendingLevel=$level, dailyCount=${_state.value.dailyCount}")
        if (level == null) return
        viewModelScope.launch {
            Log.d("SettingsVM", "launch: updating level to $level")
            settingsRepository.updateLevel(level)
            _state.value = _state.value.copy(level = level)
            Log.d("SettingsVM", "launch: calling triggerNextBatch($level, ${_state.value.dailyCount})")
            triggerNextBatch(level, _state.value.dailyCount)
            Log.d("SettingsVM", "launch: triggerNextBatch completed")
        }
        _state.value = _state.value.copy(
            showLevelConfirmDialog = false,
            pendingLevel = null
        )
    }

    /** 用户取消修改难度。 */
    fun cancelLevelChange() {
        _state.value = _state.value.copy(
            showLevelConfirmDialog = false,
            pendingLevel = null
        )
    }

    // ── Daily count change: request → confirm → persist (no generation) ──

    /** 用户点击 ± 后调用：暂存并弹出确认弹窗。 */
    fun requestCountChange(newCount: Int) {
        if (newCount < 1 || newCount > 5) return
        if (newCount == _state.value.dailyCount) return // 未变更
        _state.value = _state.value.copy(
            pendingCount = newCount,
            showCountConfirmDialog = true
        )
    }

    /** 用户确认修改篇数。 */
    fun confirmCountChange() {
        val count = _state.value.pendingCount ?: return
        viewModelScope.launch {
            settingsRepository.updateDailyArticleCount(count)
            _state.value = _state.value.copy(dailyCount = count)
            // 仅写 DB，不触发新批次生成。
            // 篇数变化在下一次分配批次时通过 dailyCountSnapshot 体现。
        }
        _state.value = _state.value.copy(
            showCountConfirmDialog = false,
            pendingCount = null
        )
    }

    /** 用户取消修改篇数。 */
    fun cancelCountChange() {
        _state.value = _state.value.copy(
            showCountConfirmDialog = false,
            pendingCount = null
        )
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
