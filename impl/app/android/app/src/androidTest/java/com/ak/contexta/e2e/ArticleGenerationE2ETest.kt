package com.ak.contexta.e2e

import android.util.Log
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.Configuration
import androidx.work.WorkManager
import com.ak.contexta.MainActivity
import com.ak.contexta.data.remote.dto.ChatCompletionResponse
import com.ak.contexta.data.remote.dto.ChatResponseMessage
import com.ak.contexta.data.remote.dto.Choice
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

/**
 * End-to-end test for the article generation pipeline.
 *
 * Flow:
 *   1. App launch → Onboarding screen
 *   2. Complete 3-step onboarding (MEDIUM level, 1 article/day)
 *   3. Home triggers batch creation → WorkManager schedules generation
 *   4. WorkManager runs → calls mocked DeepSeekApi → writes article to DB
 *   5. Home screen displays the generated article
 *   6. Tap article → Reading screen shows paragraphs
 *
 * Mocking strategy:
 *   [FakeDeepSeekApi] replaces the real [com.ak.contexta.data.remote.DeepSeekApi]
 *   via Hilt's [BindValue], returning a realistic LLM article XML.
 *   Everything else (Room DB, WorkManager, UI) runs in full production mode.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class ArticleGenerationE2ETest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    /** Replaces the production DeepSeekApi with a fake that returns deterministic responses. */
    @BindValue
    @JvmField
    val fakeDeepSeekApi = FakeDeepSeekApi()

    /** Injected HiltWorkerFactory for WorkManager initialization in the test. */
    @Inject
    lateinit var hiltWorkerFactory: androidx.hilt.work.HiltWorkerFactory

    /** Realistic 5-paragraph article XML returned by the fake LLM API. */
    private val articleXml = buildString {
        appendLine("<title>A Walk in the Park</title>")
        appendLine("<paragraph>The sun was shining brightly over the city park.</paragraph>")
        appendLine("<translation>阳光明媚地照在城市公园上。</translation>")
        appendLine("<paragraph>Children were playing happily on the green grass.</paragraph>")
        appendLine("<translation>孩子们在绿色的草地上快乐地玩耍。</translation>")
        appendLine("<paragraph>An elderly couple sat on a bench reading books.</paragraph>")
        appendLine("<translation>一对老夫妇坐在长椅上读书。</translation>")
        appendLine("<paragraph>The gentle breeze carried the scent of fresh flowers.</paragraph>")
        appendLine("<translation>微风带来了鲜花的香气。</translation>")
        appendLine("<paragraph>It was a perfect day for a walk in the park.</paragraph>")
        appendLine("<translation>这是在公园散步的完美一天。</translation>")
    }

    @Before
    fun setup() {
        // Step 1: Inject Hilt members (@BindValue is bound by hiltRule's @Before)
        hiltRule.inject()

        val context = InstrumentationRegistry.getInstrumentation().targetContext

        // Step 2: Initialize WorkManager with HiltWorkerFactory so that
        // ArticleGenerationWorker is created via Hilt injection.
        try {
            WorkManager.initialize(
                context,
                Configuration.Builder()
                    .setWorkerFactory(hiltWorkerFactory)
                    .setMinimumLoggingLevel(Log.DEBUG)
                    .build()
            )
        } catch (e: IllegalStateException) {
            // WorkManager already initialized (e.g. from a previous test in the process)
        }

        // Step 3: Clear the database so the app starts on the Onboarding screen
        context.deleteDatabase("contexta.db")

        // Step 4: Configure the mock LLM response that ArticleGenerationWorker will receive
        fakeDeepSeekApi.response = ChatCompletionResponse(
            id = "e2e-test-article-001",
            choices = listOf(
                Choice(
                    index = 0,
                    message = ChatResponseMessage(
                        role = "assistant",
                        content = articleXml
                    ),
                    finish_reason = "stop"
                )
            )
        )
    }

    @Test
    fun articleGeneration_lifecycle_full() {
        // ════════════════════════════════════════════
        // Phase 1: Complete onboarding (3 steps)
        // ════════════════════════════════════════════

        composeTestRule.waitForIdle()

        // Step 1 — Select MEDIUM level
        composeTestRule.onNodeWithText("中级 · MEDIUM")
            .performScrollTo()
            .performClick()
        composeTestRule.waitForIdle()

        // Click "下一步"
        composeTestRule.onNodeWithText("下一步")
            .performScrollTo()
            .performClick()
        composeTestRule.waitForIdle()

        // Step 2 — Select "1 篇"
        composeTestRule.onNodeWithText("1 篇")
            .performScrollTo()
            .performClick()
        composeTestRule.waitForIdle()

        // Click "下一步"
        composeTestRule.onNodeWithText("下一步")
            .performScrollTo()
            .performClick()
        composeTestRule.waitForIdle()

        // Step 3 — Click "开始学习" to complete onboarding
        composeTestRule.onNodeWithText("开始学习")
            .performScrollTo()
            .performClick()

        // ════════════════════════════════════════════
        // Phase 2: Wait for WorkManager to generate articles
        // ════════════════════════════════════════════
        //
        // After onboarding, HomeViewModel creates a batch and schedules
        // WorkManager. The worker calls the fake API, parses the response,
        // and writes the article to Room. The Home screen observes the
        // Room Flow and displays the article card.
        //
        // Timeout is generous (60 s) to account for WorkManager scheduling
        // delays on a physical device.

        composeTestRule.waitUntil(timeoutMillis = 60_000) {
            composeTestRule
                .onAllNodesWithText("A Walk in the Park", substring = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }

        // Verify the fake API was actually called (pipeline executed)
        assertTrue(
            "The fake DeepSeekApi should have been called by ArticleGenerationWorker",
            fakeDeepSeekApi.callCount > 0
        )

        // ════════════════════════════════════════════
        // Phase 3: Tap article → Reading screen
        // ════════════════════════════════════════════

        composeTestRule.onNodeWithText("A Walk in the Park")
            .performClick()

        composeTestRule.waitForIdle()

        // ════════════════════════════════════════════
        // Phase 4: Verify reading screen content
        // ════════════════════════════════════════════

        // Article title in the app bar
        composeTestRule.onNodeWithText("A Walk in the Park")
            .assertIsDisplayed()

        // Paragraph content (opening sentence)
        composeTestRule.onNodeWithText(
            "The sun was shining brightly over the city park."
        ).assertIsDisplayed()

        // Paragraph content (middle)
        composeTestRule.onNodeWithText(
            "Children were playing happily on the green grass."
        ).assertIsDisplayed()

        // Translation mode toggle
        composeTestRule.onNodeWithText("译文")
            .assertIsDisplayed()

        // Back button
        composeTestRule.onNodeWithText("←")
            .assertIsDisplayed()

        // "朗读本段" action
        composeTestRule.onNodeWithText("朗读本段")
            .assertIsDisplayed()
    }
}
