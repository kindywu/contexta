package com.ak.contexta.ui.reading

import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.model.WordDetail
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import com.ak.contexta.domain.tts.TtsEngine
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** 记录发声，并允许测试以指定 id 触发完成回调（模拟自然结束 / 迟到事件）。 */
private class FakeTtsEngine : TtsEngine {
    var available = true
    var lastUtteranceId: String? = null
    var lastSpokenText: String? = null
    var stoppedCount = 0
    private var onSpeakingFinished: ((String?) -> Unit)? = null
    private var counter = 0L

    override fun isAvailable(): Boolean = available
    override fun unavailabilityReason(): String? = null

    override fun speak(text: String, speed: Float): String? {
        if (!available) return null
        lastSpokenText = text
        lastUtteranceId = "ctx-${counter++}"
        return lastUtteranceId
    }

    override fun stop() {
        stoppedCount++
        // 与真实引擎一致：stop 触发当前 utterance 的完成回调
        val id = lastUtteranceId
        lastUtteranceId = null
        onSpeakingFinished?.invoke(id)
    }

    override fun setOnSpeakingFinished(callback: ((String?) -> Unit)?) {
        onSpeakingFinished = callback
    }

    /** 模拟某次 utterance 结束（自然播完或迟到的旧事件）。 */
    fun finishUtterance(utteranceId: String?) {
        onSpeakingFinished?.invoke(utteranceId)
    }
}

class ReadingViewModelTest {

    private val articleRepository: ArticleRepository = mockk()
    private val settingsRepository: SettingsRepository = mockk()
    private val wordRepository: WordRepository = mockk()
    private val vocabularyRepository: VocabularyRepository = mockk()
    private val statsRepository: StatsRepository = mockk()
    private val llmClient: LlmClient = mockk()
    private val ttsEngine = FakeTtsEngine()

    private lateinit var viewModel: ReadingViewModel

    @Before
    fun setUp() {
        // UnconfinedTestDispatcher：loadArticle/showWordSheet 的 launch 体同步执行，断言无需推进虚拟时钟
        Dispatchers.setMain(UnconfinedTestDispatcher())
        viewModel = ReadingViewModel(
            articleRepository, settingsRepository, wordRepository,
            vocabularyRepository, statsRepository, llmClient, ttsEngine
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    /** 载入两段文章（Hello world. / Second paragraph.）。同步 stub + 同步 launch。 */
    private fun loadParagraphs() {
        // readCompletedAt 非空 → 已读 → 不启动 readTimer 无限循环（否则 runTest 虚拟时钟推进时会死循环）
        coEvery { articleRepository.getArticle(1L) } returns Article(
            id = 1L, batchId = 1L, orderIndex = 0, contentCategory = "science",
            title = "Test", status = ArticleStatus.SUCCESS,
            generationStartedAt = null, generationCompletedAt = null,
            retryCount = 0, accumulatedReadSeconds = 0, readCompletedAt = "2026-01-01T00:00:00Z",
            lastRetryAt = null,
            paragraphs = listOf(
                ArticleParagraph(0, "Hello world.", "你好世界。"),
                ArticleParagraph(1, "Second paragraph.", "第二段。")
            )
        )
        coEvery { settingsRepository.getSettings() } returns null
        coEvery { vocabularyRepository.getActiveWords() } returns emptyList()
        coEvery { statsRepository.recordReadingActivity() } returns Unit
        viewModel.loadArticle(1L)
    }

    // ─── playParagraph ─────────────────────────────────────────

    @Test
    fun `playParagraph sets speaking index and clears full article state`() = runTest {
        loadParagraphs()
        viewModel.playParagraph(0)
        assertEquals(0, viewModel.state.value.speakingParagraphIndex)
        assertEquals("Hello world.", ttsEngine.lastSpokenText)
        assertFalse(viewModel.state.value.isSpeakingFullArticle)
    }

    @Test
    fun `tapping the same paragraph again stops playback`() = runTest {
        loadParagraphs()
        viewModel.playParagraph(0)
        viewModel.playParagraph(0)
        assertEquals(1, ttsEngine.stoppedCount)
        assertNull(viewModel.state.value.speakingParagraphIndex)
    }

    @Test
    fun `natural completion clears speaking state`() = runTest {
        loadParagraphs()
        viewModel.playParagraph(0)
        ttsEngine.finishUtterance(ttsEngine.lastUtteranceId)
        assertNull(viewModel.state.value.speakingParagraphIndex)
    }

    @Test
    fun `stale onStop from a previous utterance does not clear new state`() = runTest {
        loadParagraphs()
        viewModel.playParagraph(0)
        val staleId = ttsEngine.lastUtteranceId
        viewModel.playParagraph(1)
        // 旧 utterance 的迟到 onStop（id 不匹配 → 不应清状态）
        ttsEngine.finishUtterance(staleId)
        assertEquals(1, viewModel.state.value.speakingParagraphIndex)
        // 新 utterance 正常结束后才清
        ttsEngine.finishUtterance(ttsEngine.lastUtteranceId)
        assertNull(viewModel.state.value.speakingParagraphIndex)
    }

    @Test
    fun `unavailable TTS shows snackbar and keeps state unchanged`() = runTest {
        loadParagraphs()
        ttsEngine.available = false
        viewModel.playParagraph(0)
        assertEquals(ReadingViewModel.TTS_ERROR_MESSAGE, viewModel.state.value.snackbarMessage)
        assertTrue(viewModel.state.value.openTtsSettings)
        assertNull(viewModel.state.value.speakingParagraphIndex)
    }

    // ─── 与全文 / 单词播放的互斥 ────────────────────────────────

    @Test
    fun `starting full article playback clears paragraph speaking state`() = runTest {
        loadParagraphs()
        viewModel.playParagraph(0)
        viewModel.toggleFullArticlePlayback()
        assertTrue(viewModel.state.value.isSpeakingFullArticle)
        assertNull(viewModel.state.value.speakingParagraphIndex)
        // 全文播完清空全部
        ttsEngine.finishUtterance(ttsEngine.lastUtteranceId)
        assertFalse(viewModel.state.value.isSpeakingFullArticle)
    }

    @Test
    fun `word pronunciation interrupts paragraph playback and clears its state`() = runTest {
        loadParagraphs()
        coEvery { wordRepository.lookupWord(any(), any()) } returns WordDetail(
            wordId = 1L, spellingDisplay = "hello", phoneticIpa = null,
            primarySense = null, allSenses = emptyList()
        )
        viewModel.showWordSheet("hello")
        viewModel.playParagraph(0)
        viewModel.playWordPronunciation()
        assertNull(viewModel.state.value.speakingParagraphIndex)
        assertFalse(viewModel.state.value.isSpeakingFullArticle)
    }
}
