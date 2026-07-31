package com.ak.contexta.ui.vocabulary

import com.ak.contexta.domain.model.UserSettings
import com.ak.contexta.domain.model.VocabStatus
import com.ak.contexta.domain.model.VocabWord
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
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
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/** 记录发声的假 TTS 引擎。 */
private class FakeTtsEngine : TtsEngine {
    var available = true
    var lastSpokenText: String? = null

    override fun isAvailable(): Boolean = available
    override fun unavailabilityReason(): String? = null

    override fun speak(text: String, speed: Float): String? {
        if (!available) return null
        lastSpokenText = text
        return "ctx"
    }

    override fun stop() {}

    override fun setOnSpeakingFinished(callback: ((String?) -> Unit)?) {}
}

class VocabularyViewModelTest {

    private val vocabularyRepository: VocabularyRepository = mockk()
    private val settingsRepository: SettingsRepository = mockk()
    private val ttsEngine = FakeTtsEngine()

    private lateinit var viewModel: VocabularyViewModel

    private val words = listOf(
        VocabWord(
            entryId = 1L, wordId = 1L, instanceNumber = 1, status = VocabStatus.NEW,
            correctReviewStreak = 0, spellingDisplay = "hello",
            phoneticIpa = null, allSenses = emptyList()
        ),
        VocabWord(
            entryId = 2L, wordId = 2L, instanceNumber = 1, status = VocabStatus.NEW,
            correctReviewStreak = 0, spellingDisplay = "world",
            phoneticIpa = null, allSenses = emptyList()
        )
    )

    /** init{loadVocabulary()} 在构造时同步执行（UnconfinedTestDispatcher），stub 必须先于构造。 */
    private fun createViewModel(autoPlayAudio: Boolean, words: List<VocabWord> = this.words) {
        coEvery { settingsRepository.getSettings() } returns UserSettings(autoPlayAudio = autoPlayAudio)
        coEvery { vocabularyRepository.getActiveWords() } returns words
        viewModel = VocabularyViewModel(vocabularyRepository, settingsRepository, ttsEngine)
    }

    @Before
    fun setUp() {
        // UnconfinedTestDispatcher：构造时的 loadVocabulary launch 体同步执行，断言无需推进虚拟时钟
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ─── 自动朗读（autoPlayAudio 设置） ─────────────────────────
    // 注：生产代码对单词列表 .shuffled()，顺序随机——涉及具体单词的断言必须用单元素列表，
    // 涉及"切到下一个"的断言用相对比较（新词 ≠ 旧词），不依赖随机顺序。

    @Test
    fun `shows first word with auto-play when autoPlayAudio is enabled`() = runTest {
        createViewModel(autoPlayAudio = true, words = listOf(words[0]))
        assertEquals("hello", viewModel.state.value.currentWord?.word)
        assertEquals("hello", ttsEngine.lastSpokenText)
    }

    @Test
    fun `advancing to next word auto-plays it`() = runTest {
        createViewModel(autoPlayAudio = true)
        val firstWord = viewModel.state.value.currentWord?.word
        viewModel.goNext()
        val secondWord = viewModel.state.value.currentWord?.word
        assertNotNull(secondWord)
        assertNotEquals(firstWord, secondWord)
        assertEquals(secondWord, ttsEngine.lastSpokenText)
    }

    @Test
    fun `does not auto-play when autoPlayAudio is disabled`() = runTest {
        createViewModel(autoPlayAudio = false, words = listOf(words[0]))
        assertEquals("hello", viewModel.state.value.currentWord?.word)
        assertNull(ttsEngine.lastSpokenText)
    }

    @Test
    fun `auto-play silently skips when TTS unavailable`() = runTest {
        ttsEngine.available = false
        createViewModel(autoPlayAudio = true, words = listOf(words[0]))
        assertEquals("hello", viewModel.state.value.currentWord?.word)
        assertNull(ttsEngine.lastSpokenText)
    }
}
