package com.ak.contexta.ui.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.usecase.ActivateSeedBatchUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OnboardingState(
    val currentStep: Int = 1,
    val selectedLevel: String? = null,
    val selectedDailyCount: Int? = null
)

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val settingsRepository: SettingsRepository,
    private val activateSeedBatch: ActivateSeedBatchUseCase
) : ViewModel() {

    private val _state = MutableStateFlow(OnboardingState())
    val state: StateFlow<OnboardingState> = _state.asStateFlow()

    /** Returns true if user has already completed onboarding */
    suspend fun isAlreadyOnboarded(): Boolean = settingsRepository.isOnboarded()

    fun selectLevel(level: String) {
        _state.value = _state.value.copy(selectedLevel = level)
    }

    fun selectDailyCount(count: Int) {
        _state.value = _state.value.copy(selectedDailyCount = count)
    }

    fun nextStep() {
        val current = _state.value.currentStep
        if (current < 3) {
            _state.value = _state.value.copy(currentStep = current + 1)
        }
    }

    fun previousStep() {
        val current = _state.value.currentStep
        if (current > 1) {
            _state.value = _state.value.copy(currentStep = current - 1)
        }
    }

    fun completeOnboarding(onComplete: () -> Unit) {
        val s = _state.value
        val level = s.selectedLevel ?: return
        val dailyCount = s.selectedDailyCount ?: return

        viewModelScope.launch {
            settingsRepository.completeOnboarding(level, dailyCount)
            activateSeedBatch(level, dailyCount) // 激活匹配的种子批次，用户立即看到文章
            onComplete()
        }
    }
}
