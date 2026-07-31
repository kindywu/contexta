package com.ak.contexta.ui.reading

import android.content.Intent
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.generation.buildWordLookupSystemPrompt
import com.ak.contexta.domain.generation.buildWordLookupUserPrompt
import com.ak.contexta.domain.generation.parseWordLlmResponse
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.WordSense
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import com.ak.contexta.domain.tts.TtsEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
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
    val vocabularyWords: Set<String> = emptySet(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val wordSheetData: WordSheetData? = null,
    val isWordSheetVisible: Boolean = false,
    val snackbarMessage: String? = null,
    val openTtsSettings: Boolean = false,
    val ttsSpeed: Float = 1.0f,
    val isReadCompleted: Boolean = false,
    val isSpeakingFullArticle: Boolean = false,
    val speakingParagraphIndex: Int? = null
)

enum class TranslationMode(val label: String) {
    FULL("完全显示"),
    DIM("淡化"),
    BLURRED("模糊"),
    HIDDEN("隐藏");

    val next: TranslationMode
        get() = entries[(ordinal + 1) % entries.size]
}

data class WordSheetData(
    val word: String,
    val isLoading: Boolean = false,
    val phonetic: String? = null,
    val senses: List<WordSenseUi> = emptyList(),
    val isInVocabulary: Boolean = false,
    val wordId: Long? = null,
    val vocabularyEntryId: Long? = null
)

/** 词性分组后的单个义项。同词性义项在 [WordSheetData.senses] 中相邻排列。 */
data class WordSenseUi(
    val partOfSpeech: String,
    val englishDefinition: String,
    val chineseMeaning: String
)

@HiltViewModel
class ReadingViewModel @Inject constructor(
    private val articleRepository: ArticleRepository,
    private val settingsRepository: SettingsRepository,
    private val wordRepository: WordRepository,
    private val vocabularyRepository: VocabularyRepository,
    private val statsRepository: StatsRepository,
    private val llmClient: LlmClient,
private val ttsEngine: TtsEngine
) : ViewModel() {

    private val _state = MutableStateFlow(ReadingUiState())
    val state: StateFlow<ReadingUiState> = _state.asStateFlow()

    private var articleId: Long = -1
    private var readTimerJob: Job? = null
    private var currentUtteranceId: String? = null

    init {
        // 只有当前 utterance 结束才清状态；迟到的旧 utterance 回调（快速切换播放时）被 id 校验过滤
        ttsEngine.setOnSpeakingFinished { utteranceId ->
            if (utteranceId == currentUtteranceId) {
                currentUtteranceId = null
                _state.value = _state.value.copy(
                    isSpeakingFullArticle = false,
                    speakingParagraphIndex = null
                )
            }
        }
    }

    fun loadArticle(articleId: Long) {
        this.articleId = articleId
        readTimerJob?.cancel()
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
                val alreadyRead = article.readCompletedAt != null
                val vocabWords = vocabularyRepository.getActiveWords()
                    .map { WordRepository.normalize(it.spellingDisplay) }
                    .toSet()
                _state.value = _state.value.copy(
                    title = article.title ?: "Untitled",
                    paragraphs = article.paragraphs,
                    translationMode = savedMode,
                    revealedParagraphs = emptySet(),
                    isLoading = false,
                    isReadCompleted = alreadyRead,
                    vocabularyWords = vocabWords,
                    // 切换文章时重置段落播放状态，防止上一篇文章的状态残留
                    speakingParagraphIndex = null
                )
                // Record reading activity for stats
                statsRepository.recordReadingActivity()
                // Start timer to track reading duration
                if (!alreadyRead) {
                    startReadTimer()
                }
            } else {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "文章未找到"
                )
            }
        }
    }

    private fun startReadTimer() {
        readTimerJob?.cancel()
        readTimerJob = viewModelScope.launch {
            while (true) {
                delay(15_000L) // tick every 15 seconds
                val currentId = articleId
                if (currentId < 0) break
                articleRepository.addReadSeconds(currentId, 15)
                articleRepository.tryMarkReadCompleted(currentId)
                // Refresh read status
                val article = articleRepository.getArticle(currentId)
                if (article?.readCompletedAt != null) {
                    _state.value = _state.value.copy(isReadCompleted = true)
                    break
                }
            }
        }
    }

    /** Manually mark the article as read (bypasses 120s threshold). */
    fun markAsRead() {
        viewModelScope.launch {
            articleRepository.forceMarkReadCompleted(articleId)
            _state.value = _state.value.copy(isReadCompleted = true)
            readTimerJob?.cancel()
        }
    }

    override fun onCleared() {
        super.onCleared()
        readTimerJob?.cancel()
    }

    fun cycleTranslationMode() {
        val current = _state.value.translationMode
        val next = current.next
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
                    val result = llmClient.call(
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
                _state.value = _state.value.copy(
                    wordSheetData = WordSheetData(
                        word = detail.spellingDisplay,
                        isLoading = false,
                        phonetic = detail.phoneticIpa,
                        senses = groupSensesByPartOfSpeech(detail.allSenses),
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

    /** 按词性分组（组序 = 义项首次出现序，保留语境匹配义项优先），同词性义项相邻排列。 */
    private fun groupSensesByPartOfSpeech(senses: List<WordSense>): List<WordSenseUi> {
        val sensesByPos = LinkedHashMap<String, MutableList<WordSense>>()
        senses.forEach { sense ->
            sensesByPos.getOrPut(sense.partOfSpeech) { mutableListOf() }.add(sense)
        }
        return sensesByPos.flatMap { (pos, items) ->
            items.map { WordSenseUi(pos, it.englishDefinition, it.chineseMeaning) }
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
        if (!ttsEngine.isAvailable()) {
            _state.value = _state.value.copy(
                snackbarMessage = TTS_ERROR_MESSAGE,
                openTtsSettings = true
            )
            return
        }
        val id = ttsEngine.speak(word, speed)
        if (id != null) {
            currentUtteranceId = id
            // Word pronunciation supersedes full-article and paragraph playback
            _state.value = _state.value.copy(
                isSpeakingFullArticle = false,
                speakingParagraphIndex = null
            )
        }
    }

    /** Speak a paragraph. Tapping the currently speaking paragraph stops it. */
    fun playParagraph(index: Int) {
        if (_state.value.speakingParagraphIndex == index) {
            ttsEngine.stop()
            return
        }
        val speed = _state.value.ttsSpeed
        if (!ttsEngine.isAvailable()) {
            _state.value = _state.value.copy(
                snackbarMessage = TTS_ERROR_MESSAGE,
                openTtsSettings = true
            )
            return
        }
        val text = _state.value.paragraphs[index].englishText
        val id = ttsEngine.speak(text, speed)
        if (id != null) {
            currentUtteranceId = id
            _state.value = _state.value.copy(
                isSpeakingFullArticle = false,
                speakingParagraphIndex = index
            )
        }
    }

    /** Toggle full-article playback: start if idle, stop if speaking. */
    fun toggleFullArticlePlayback() {
        if (_state.value.isSpeakingFullArticle) {
            ttsEngine.stop()
            _state.value = _state.value.copy(isSpeakingFullArticle = false)
            return
        }
        val fullText = _state.value.paragraphs
            .joinToString(" ") { it.englishText }
        if (!ttsEngine.isAvailable()) {
            _state.value = _state.value.copy(
                snackbarMessage = TTS_ERROR_MESSAGE,
                openTtsSettings = true
            )
            return
        }
        val id = ttsEngine.speak(fullText, _state.value.ttsSpeed)
        if (id != null) {
            currentUtteranceId = id
            _state.value = _state.value.copy(
                isSpeakingFullArticle = true,
                speakingParagraphIndex = null
            )
        }
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
        val word = _state.value.wordSheetData?.word ?: return
        viewModelScope.launch {
            val entryId = vocabularyRepository.addWord(wordId)
            if (entryId != null) {
                statsRepository.recordWordAdded()
                wordRepository.invalidateCache(word)
            }
            val data = _state.value.wordSheetData?.copy(
                isInVocabulary = entryId != null,
                vocabularyEntryId = entryId
            )
            _state.value = _state.value.copy(
                wordSheetData = data,
                vocabularyWords = if (entryId != null) {
                    _state.value.vocabularyWords + word
                } else {
                    _state.value.vocabularyWords
                }
            )
        }
    }

    fun removeFromVocabulary() {
        val entryId = _state.value.wordSheetData?.vocabularyEntryId ?: return
        val word = _state.value.wordSheetData?.word ?: return
        viewModelScope.launch {
            vocabularyRepository.removeWord(entryId)
            wordRepository.invalidateCache(word)
            val data = _state.value.wordSheetData?.copy(
                isInVocabulary = false,
                vocabularyEntryId = null
            )
            _state.value = _state.value.copy(
                wordSheetData = data,
                vocabularyWords = _state.value.vocabularyWords - word
            )
        }
    }
}
