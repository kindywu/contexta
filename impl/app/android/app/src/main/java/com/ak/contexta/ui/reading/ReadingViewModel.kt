package com.ak.contexta.ui.reading

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ReadingUiState(
    val title: String? = null,
    val paragraphs: List<ArticleParagraph> = emptyList(),
    val translationMode: TranslationMode = TranslationMode.FULL,
    val isLoading: Boolean = true,
    val error: String? = null,
    val wordSheetData: WordSheetData? = null,
    val isWordSheetVisible: Boolean = false
)

enum class TranslationMode(val label: String) {
    FULL("完全显示"),
    BLURRED("模糊"),
    HIDDEN("隐藏")
}

data class WordSheetData(
    val word: String,
    val phonetic: String? = null,
    val translation: String? = null,
    val definitions: List<String> = emptyList(),
    val exampleEn: String? = null,
    val exampleZh: String? = null,
    val isInVocabulary: Boolean = false
)

@HiltViewModel
class ReadingViewModel @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val wordRepository: WordRepository,
    private val vocabularyRepository: VocabularyRepository
) : ViewModel() {

    private val _state = MutableStateFlow(ReadingUiState())
    val state: StateFlow<ReadingUiState> = _state.asStateFlow()

    private var articleId: Long = -1

    fun loadArticle(articleId: Long) {
        this.articleId = articleId
        viewModelScope.launch {
            val article = articleRepository.getArticle(articleId)
            if (article != null) {
                _state.value = _state.value.copy(
                    title = article.title ?: "Untitled",
                    paragraphs = article.paragraphs,
                    isLoading = false
                )
            } else {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "文章未找到"
                )
            }
        }
    }

    fun cycleTranslationMode() {
        val current = _state.value.translationMode
        val next = when (current) {
            TranslationMode.FULL -> TranslationMode.BLURRED
            TranslationMode.BLURRED -> TranslationMode.HIDDEN
            TranslationMode.HIDDEN -> TranslationMode.FULL
        }
        _state.value = _state.value.copy(translationMode = next)
    }

    fun revealTranslation(paragraphIndex: Int) {
        // In blurred mode, toggle blur for a specific paragraph
        // This is handled in the UI layer
    }

    fun showWordSheet(word: String) {
        viewModelScope.launch {
            val normalized = com.ak.contexta.domain.repository.WordRepository.normalize(word)
            val detail = wordRepository.lookupWord(normalized) { _ -> null }

            if (detail != null) {
                val primarySense = detail.primarySense
                _state.value = _state.value.copy(
                    wordSheetData = WordSheetData(
                        word = detail.spellingDisplay,
                        phonetic = detail.phoneticIpa,
                        translation = primarySense?.chineseMeaning,
                        definitions = detail.allSenses.map { it.chineseMeaning },
                        exampleEn = primarySense?.examples?.firstOrNull()?.sentenceEn,
                        exampleZh = primarySense?.examples?.firstOrNull()?.sentenceZh,
                        isInVocabulary = detail.isInVocabulary
                    ),
                    isWordSheetVisible = true
                )
            } else {
                // Fallback: show raw word without lookup data
                _state.value = _state.value.copy(
                    wordSheetData = WordSheetData(
                        word = normalized,
                        isInVocabulary = false
                    ),
                    isWordSheetVisible = true
                )
            }
        }
    }

    fun hideWordSheet() {
        _state.value = _state.value.copy(
            isWordSheetVisible = false,
            wordSheetData = null
        )
    }

    fun addToVocabulary(wordId: Long) {
        viewModelScope.launch {
            vocabularyRepository.addWord(wordId)
            hideWordSheet()
        }
    }

    fun removeFromVocabulary(entryId: Long) {
        viewModelScope.launch {
            vocabularyRepository.removeWord(entryId)
            hideWordSheet()
        }
    }
}
