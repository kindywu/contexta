package com.ak.contexta.ui.vocabulary

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
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
    val isLoading: Boolean = true
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
    private val settingsRepository: SettingsRepository
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

            vocabularyRepository.observeActive().collect { list ->
                vocabList = list

                if (list.isEmpty()) {
                    _state.value = VocabularyUiState(
                        totalCount = 0,
                        isLoading = false
                    )
                } else {
                    val currentIdx = _state.value.currentIndex.coerceIn(0, list.size - 1)
                    val item = list[currentIdx]

                    _state.value = VocabularyUiState(
                        totalCount = list.size,
                        currentIndex = currentIdx,
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
                        isLoading = false
                    )
                }
            }
        }
    }

    fun markCorrect() {
        val current = _state.value.currentWord ?: return
        viewModelScope.launch {
            vocabularyRepository.markCorrect(current.entryId, masteryThreshold)
            advanceToNext()
        }
    }

    fun markIncorrect() {
        val current = _state.value.currentWord ?: return
        viewModelScope.launch {
            vocabularyRepository.markIncorrect(current.entryId)
            advanceToNext()
        }
    }

    private fun advanceToNext() {
        val nextIndex = _state.value.currentIndex + 1
        if (nextIndex >= vocabList.size) {
            // Reached end — reload to refresh list
            loadVocabulary()
        } else {
            _state.value = _state.value.copy(currentIndex = nextIndex)
            loadCurrentWord()
        }
    }

    private fun loadCurrentWord() {
        val idx = _state.value.currentIndex
        if (idx < vocabList.size) {
            val item = vocabList[idx]
            _state.value = _state.value.copy(
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
                )
            )
        }
    }
}
