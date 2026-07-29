package com.ak.contexta.ui.reading

import android.content.Intent
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.data.remote.LlmCaller
import com.ak.contexta.domain.generation.buildWordLookupSystemPrompt
import com.ak.contexta.domain.generation.buildWordLookupUserPrompt
import com.ak.contexta.domain.generation.parseWordLlmResponse
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import com.ak.contexta.domain.tts.TtsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ReadingUiState(
    val title: String? = null,
    val paragraphs: List<ArticleParagraph> = emptyList(),
    val translationMode: TranslationMode = TranslationMode.FULL,
    val revealedParagraphs: Set<Int> = emptySet(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val wordSheetData: WordSheetData? = null,
    val isWordSheetVisible: Boolean = false,
    val snackbarMessage: String? = null,
    val openTtsSettings: Boolean = false,
    val ttsSpeed: Float = 1.0f
)

enum class TranslationMode(val label: String) {
    FULL("完全显示"),
    BLURRED("模糊"),
    HIDDEN("隐藏")
}

data class WordSheetData(
    val word: String,
    val isLoading: Boolean = false,
    val phonetic: String? = null,
    val translation: String? = null,
    val definitions: List<String> = emptyList(),
    val exampleEn: String? = null,
    val exampleZh: String? = null,
    val isInVocabulary: Boolean = false,
    val wordId: Long? = null,
    val vocabularyEntryId: Long? = null
)

@HiltViewModel
class ReadingViewModel @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val wordRepository: WordRepository,
    private val vocabularyRepository: VocabularyRepository,
    private val llmCaller: LlmCaller,
private val ttsManager: TtsManager
) : ViewModel() {

    private val _state = MutableStateFlow(ReadingUiState())
    val state: StateFlow<ReadingUiState> = _state.asStateFlow()

    private var articleId: Long = -1

    fun loadArticle(articleId: Long) {
        this.articleId = articleId
        viewModelScope.launch {
            val article = articleRepository.getArticle(articleId)

            // Read the saved translation mode from settings
            val savedMode = settingsRepository.getSettings()
                ?.translationDisplayMode
                ?.let { modeStr ->
                    try {
                        TranslationMode.valueOf(modeStr)
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                } ?: TranslationMode.FULL

            if (article != null) {
                _state.value = _state.value.copy(
                    title = article.title ?: "Untitled",
                    paragraphs = article.paragraphs,
                    translationMode = savedMode,
                    revealedParagraphs = emptySet(),
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
        _state.value = _state.value.copy(
            translationMode = next,
            revealedParagraphs = emptySet()
        )
        // Persist the change so it's the default next time
        viewModelScope.launch {
            settingsRepository.updateTranslationMode(next.name)
        }
    }

    fun revealTranslation(paragraphIndex: Int) {
        _state.value = _state.value.copy(
            revealedParagraphs = _state.value.revealedParagraphs + paragraphIndex
        )
        // Auto-blur after 10 seconds
        viewModelScope.launch {
            delay(10_000L)
            _state.value = _state.value.copy(
                revealedParagraphs = _state.value.revealedParagraphs - paragraphIndex
            )
        }
    }

    fun showWordSheet(word: String) {
        val normalized = WordRepository.normalize(word)

        // Show sheet immediately with loading state
        _state.value = _state.value.copy(
            wordSheetData = WordSheetData(
                word = normalized,
                isLoading = true
            ),
            isWordSheetVisible = true
        )

        // Launch async lookup
        viewModelScope.launch {
            val detail = try {
                wordRepository.lookupWord(normalized) { rawWord ->
                    // LLM fallback: call DeepSeek for word definition
                    val result = llmCaller.call(
                        buildWordLookupSystemPrompt(),
                        buildWordLookupUserPrompt(rawWord)
                    )
                    val parsed = parseWordLlmResponse(result.content)
                    if (parsed != null) {
                        // Persist to DB, then return the saved WordDetail with proper IDs
                        wordRepository.saveLlmResult(
                            spellingDisplay = parsed.spellingDisplay,
                            phoneticIpa = parsed.phoneticIpa,
                            senses = parsed.allSenses,
                            normalized = WordRepository.normalize(parsed.spellingDisplay)
                        )
                    } else {
                        Log.w(TAG, "Failed to parse LLM response for word: $rawWord")
                        null
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Word lookup failed for '$word': ${e.message}")
                null
            }

            if (detail != null) {
                val primarySense = detail.primarySense
                _state.value = _state.value.copy(
                    wordSheetData = WordSheetData(
                        word = detail.spellingDisplay,
                        isLoading = false,
                        phonetic = detail.phoneticIpa,
                        translation = primarySense?.chineseMeaning,
                        definitions = detail.allSenses.map { "${it.partOfSpeech} ${it.chineseMeaning}" },
                        exampleEn = primarySense?.examples?.firstOrNull()?.sentenceEn,
                        exampleZh = primarySense?.examples?.firstOrNull()?.sentenceZh,
                        isInVocabulary = detail.isInVocabulary,
                        wordId = detail.wordId,
                        vocabularyEntryId = detail.vocabularyEntryId
                    ),
                    isWordSheetVisible = true
                )
            } else {
                _state.value = _state.value.copy(
                    wordSheetData = WordSheetData(
                        word = normalized,
                        isLoading = false,
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

    companion object {
        private const val TAG = "ReadingVM"
        const val TTS_ERROR_MESSAGE = "语音引擎未安装，请在系统设置中开启「文字转语音」功能"
    }

    /** Toggle TTS speed between 1x and 0.5x. */
    fun toggleTtsSpeed() {
        val current = _state.value.ttsSpeed
        val next = if (current < 1.0f) 1.0f else 0.5f
        _state.value = _state.value.copy(ttsSpeed = next)
    }

    /** Speak the word currently shown in the bottom sheet. */
    fun playWordPronunciation() {
        val word = _state.value.wordSheetData?.word ?: return
        val speed = _state.value.ttsSpeed
        if (!ttsManager.isAvailable()) {
            _state.value = _state.value.copy(
                snackbarMessage = TTS_ERROR_MESSAGE,
                openTtsSettings = true
            )
            return
        }
        ttsManager.speak(word, speed)
    }

    /** Speak an arbitrary text (paragraph, sentence, etc.). */
    fun playText(text: String) {
        val speed = _state.value.ttsSpeed
        if (!ttsManager.isAvailable()) {
            _state.value = _state.value.copy(
                snackbarMessage = TTS_ERROR_MESSAGE,
                openTtsSettings = true
            )
            return
        }
        ttsManager.speak(text, speed)
    }

    /** Speak the entire article from start to finish. */
    fun playFullArticle() {
        val fullText = _state.value.paragraphs
            .joinToString(" ") { it.englishText }
        playText(fullText)
    }

    /** Clear the snackbar after it has been shown. */
    fun clearSnackbar() {
        _state.value = _state.value.copy(snackbarMessage = null, openTtsSettings = false)
    }

    /** Open system TTS settings. */
    fun openTtsSettingsIntent(): Intent {
        return Intent(TextToSpeech.Engine.ACTION_CHECK_TTS_DATA).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    fun addToVocabulary() {
        val wordId = _state.value.wordSheetData?.wordId ?: return
        viewModelScope.launch {
            vocabularyRepository.addWord(wordId)
            val data = _state.value.wordSheetData?.copy(isInVocabulary = true)
            _state.value = _state.value.copy(wordSheetData = data)
        }
    }

    fun removeFromVocabulary() {
        val entryId = _state.value.wordSheetData?.vocabularyEntryId ?: return
        viewModelScope.launch {
            vocabularyRepository.removeWord(entryId)
            val data = _state.value.wordSheetData?.copy(
                isInVocabulary = false,
                vocabularyEntryId = null
            )
            _state.value = _state.value.copy(wordSheetData = data)
        }
    }
}
