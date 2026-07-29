package com.ak.contexta.ui.vocabulary

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.tts.TtsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class VocabularyUiState(
    val totalCount: Int = 0,
    val currentIndex: Int = 0,
    val currentWord: VocabCardData? = null,
    val isLoading: Boolean = true,
    // Summary state
    val isSummary: Boolean = false,
    val reviewedCount: Int = 0,
    val newlyKnownCount: Int = 0
)

data class VocabCardData(
    val entryId: Long,
    val word: String,
    val phonetic: String?,
    val translation: String?,
    val definitions: List<String>,
    val exampleEn: String?,
    val exampleZh: String?,
    val reviewStreak: Int = 0,
    val masteryThreshold: Int = 1
)

@HiltViewModel
class VocabularyViewModel @Inject constructor(
    private val vocabularyRepository: VocabularyRepository,
    private val settingsRepository: SettingsRepository,
    private val ttsManager: TtsManager
) : ViewModel() {

    private val _state = MutableStateFlow(VocabularyUiState())
    val state: StateFlow<VocabularyUiState> = _state.asStateFlow()

    private var vocabList: List<com.ak.contexta.domain.model.VocabWord> = emptyList()
    private var masteryThreshold = 1

    init {
        loadVocabulary()
    }

    private fun loadVocabulary() {
        viewModelScope.launch {
            masteryThreshold = settingsRepository.getSettings()?.masteryThresholdN ?: 1

            val words = vocabularyRepository.getActiveWords().shuffled()
            vocabList = words

            if (words.isEmpty()) {
                _state.value = VocabularyUiState(isLoading = false)
            } else {
                showWordAt(0)
            }
        }
    }

    private fun showWordAt(index: Int) {
        if (index >= vocabList.size) {
            _state.value = _state.value.copy(
                isSummary = true,
                currentWord = null
            )
            return
        }
        val item = vocabList[index]
        val masteredCount = (_state.value.totalCount - vocabList.size).coerceAtLeast(0)
        val reviewed = _state.value.reviewedCount

        _state.value = VocabularyUiState(
            totalCount = vocabList.size + masteredCount,
            currentIndex = index,
            currentWord = VocabCardData(
                entryId = item.entryId,
                word = item.spellingDisplay,
                phonetic = item.phoneticIpa,
                translation = item.allSenses.firstOrNull()?.chineseMeaning,
                definitions = item.allSenses.map { it.chineseMeaning },
                exampleEn = item.allSenses.firstOrNull()?.examples?.firstOrNull()?.sentenceEn,
                exampleZh = item.allSenses.firstOrNull()?.examples?.firstOrNull()?.sentenceZh,
                reviewStreak = item.correctReviewStreak,
                masteryThreshold = masteryThreshold
            ),
            isLoading = false,
            reviewedCount = reviewed,
            newlyKnownCount = _state.value.newlyKnownCount
        )
    }

    fun markCorrect() {
        val current = _state.value.currentWord ?: return
        viewModelScope.launch {
            vocabularyRepository.markCorrect(current.entryId, masteryThreshold)

            // Check if word was mastered (removed from active list)
            val stillActive = vocabularyRepository.getActiveWords()
            val wasMastered = stillActive.none { it.entryId == current.entryId }

            if (wasMastered) {
                // Remove from our local list
                vocabList = vocabList.filter { it.entryId != current.entryId }
                _state.value = _state.value.copy(
                    newlyKnownCount = _state.value.newlyKnownCount + 1,
                    reviewedCount = _state.value.reviewedCount + 1
                )
            } else {
                _state.value = _state.value.copy(
                    reviewedCount = _state.value.reviewedCount + 1
                )
            }

            advanceToNext()
        }
    }

    fun markIncorrect() {
        val current = _state.value.currentWord ?: return
        viewModelScope.launch {
            vocabularyRepository.markIncorrect(current.entryId)
            _state.value = _state.value.copy(
                reviewedCount = _state.value.reviewedCount + 1
            )
            advanceToNext()
        }
    }

    private fun advanceToNext() {
        val nextIndex = _state.value.currentIndex + 1
        if (nextIndex >= vocabList.size) {
            // All done — show summary
            _state.value = _state.value.copy(
                isSummary = true,
                currentWord = null
            )
        } else {
            showWordAt(nextIndex)
        }
    }

    fun playWord() {
        val word = _state.value.currentWord?.word ?: return
        ttsManager.speak(word)
    }

    /** Restart the review session from scratch. */
    fun restart() {
        _state.value = VocabularyUiState()
        loadVocabulary()
    }
}
