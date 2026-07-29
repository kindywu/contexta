package com.ak.contexta.worker

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.ak.contexta.data.remote.LlmCaller
import com.ak.contexta.data.remote.LlmFatalException
import com.ak.contexta.data.remote.LlmRecoverableExhaustedException
import com.ak.contexta.domain.PipelineBlockingException
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.repository.ArticleRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

/**
 * Generates a single batch of articles via LLM.
 *
 * Input:
 * - batchId (Long): the batch to process
 *
 * Process:
 * 1. CAS-claim the batch (PENDING → GENERATING)
 * 2. For each article in the batch:
 *    a. CAS-claim the article (PENDING/TIMEOUT/FAILED → GENERATING)
 *    b. Call LLM with content-category prompt
 *    c. Parse response into title + paragraphs
 *    d. Write to DB (title, paragraphs; mark SUCCESS)
 *    e. On failure: mark FATAL (structural) or TIMEOUT/FAILED (recoverable)
 * 3. After all articles: check batch completion → mark READY or BLOCKED
 */
@HiltWorker
class ArticleGenerationWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val articleRepository: ArticleRepository,
    private val llmCaller: LlmCaller
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val KEY_BATCH_ID = "batchId"
        private const val KEY_APP_VERSION_CODE = "appVersionCode"

        fun buildInputData(batchId: Long, appVersionCode: Int = 0) = workDataOf(
            KEY_BATCH_ID to batchId,
            KEY_APP_VERSION_CODE to appVersionCode
        )
    }

    override suspend fun doWork(): Result {
        val batchId = inputData.getLong(KEY_BATCH_ID, -1L)
        if (batchId == -1L) return Result.failure()

        val appVersionCode = inputData.getInt(KEY_APP_VERSION_CODE, 0)

        // 1. CAS claim the batch
        if (!articleRepository.claimBatch(batchId)) {
            // Another worker already claimed this batch — it's being processed
            // or the batch is in a terminal state
            return Result.success()
        }

        return try {
            processBatch(batchId, appVersionCode)
            Result.success()
        } catch (e: PipelineBlockingException) {
            // Structural error — block the pipeline
            articleRepository.markBatchBlocked(batchId, e.message ?: "Unknown", appVersionCode)
            Result.failure()
        } catch (e: Exception) {
            // Unexpected error — worker will retry based on WorkManager backoff
            if (runAttemptCount < 2) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }

    private suspend fun processBatch(batchId: Long, appVersionCode: Int) {
        // Get articles for this batch
        val articles = articleRepository.getArticles(batchId)
        if (articles.isEmpty()) {
            articleRepository.markBatchReady(batchId)
            return
        }

        for (article in articles) {
            // Skip already completed articles
            if (article.status.name == "SUCCESS") continue

            // CAS claim the article
            if (!articleRepository.claimArticle(article.id)) continue

            try {
                // Generate article via LLM
                val systemPrompt = buildSystemPrompt()
                val userPrompt = buildUserPrompt(article.contentCategory, article.orderIndex)
                val result = llmCaller.call(systemPrompt, userPrompt)

                // Parse LLM response
                val (title, paragraphs) = parseLlmResponse(result.content)

                // Write to DB
                articleRepository.completeArticle(
                    articleId = article.id,
                    title = title,
                    paragraphs = paragraphs,
                    retryCount = result.retryCount
                )

            } catch (e: LlmFatalException) {
                // Non-recoverable — mark as FATAL so user can retry
                articleRepository.fatalArticle(article.id)
                // Continue with other articles
                continue

            } catch (e: LlmRecoverableExhaustedException) {
                // All retries exhausted — mark as FAILED for later retry
                articleRepository.failArticle(article.id, "FAILED")
                continue

            } catch (e: PipelineBlockingException) {
                // Structural — rethrow to block the batch
                articleRepository.fatalArticle(article.id)
                throw e

            } catch (e: Exception) {
                // Unexpected — mark as TIMEOUT for later retry
                articleRepository.failArticle(article.id, "TIMEOUT")
                continue
            }
        }

        // Check batch completion
        when {
            articleRepository.hasFatalArticle(batchId) -> {
                // At least one FATAL — leave as GENERATING; user needs to address
                // (Don't mark blocked unless it's structural)
            }
            articleRepository.isBatchComplete(batchId) -> {
                articleRepository.markBatchReady(batchId)
            }
            else -> {
                // Some articles failed but none FATAL — leave for retry
            }
        }
    }

    private fun buildSystemPrompt(): String = buildString {
        appendLine("You are an English language learning content creator.")
        appendLine("You create articles for Chinese learners at various difficulty levels.")
        appendLine()
        appendLine("Output format:")
        appendLine("<title>The Article Title</title>")
        appendLine("<paragraph>English sentence here.</paragraph>")
        appendLine("<translation>中文翻译。</translation>")
        appendLine("<paragraph>Next sentence.</paragraph>")
        appendLine("<translation>下一句翻译。</translation>")
        appendLine()
        appendLine("Rules:")
        appendLine("- Each paragraph must be 1-3 sentences, not longer")
        appendLine("- Each <paragraph> must be immediately followed by <translation>")
        appendLine("- Total paragraphs: 5-8")
        appendLine("- Title must be 2-8 words")
        appendLine("- Output only the XML — no explanations, no markdown")
    }

    private fun buildUserPrompt(category: String, orderIndex: Int): String = buildString {
        appendLine("Create article #$orderIndex in the category: $category")
        appendLine()
        appendLine("Guidelines for $category:")
        when (category) {
            "DAILY_CONVERSATION" -> appendLine("A natural everyday dialogue or scenario between two people.")
            "SCENE_DESCRIPTION" -> appendLine("A vivid description of a place, event, or moment.")
            "SIMPLE_STORY" -> appendLine("A short narrative with a clear beginning and end.")
            "NEWS" -> appendLine("A brief news-style report on a current or hypothetical event.")
            "EXPOSITORY" -> appendLine("An explanatory piece that teaches a concept.")
            "ARGUMENTATIVE" -> appendLine("A short argument for or against a position.")
            "PERSONAL_ESSAY" -> appendLine("A reflective first-person piece on an experience.")
            "ACADEMIC_EXCERPT" -> appendLine("A scholarly excerpt suitable for advanced readers.")
            "DEBATE_SPEECH" -> appendLine("A persuasive speech or debate opening statement.")
            "LEGAL_DOCUMENT" -> appendLine("A simplified legal clause or contract excerpt.")
            "ART_CRITICISM" -> appendLine("An analytical piece about an artwork or performance.")
            "CLASSIC_NOVEL_EXCERPT" -> appendLine("An excerpt in the style of classic English literature.")
        }
    }

    /**
     * Parse LLM response in XML format:
     * <title>...</title>
     * <paragraph>...</paragraph>
     * <translation>...</translation>
     */
    private fun parseLlmResponse(content: String): Pair<String, List<ArticleParagraph>> {
        val title = Regex("<title>([\\s\\S]*?)</title>").find(content)
            ?.groupValues?.get(1)?.trim() ?: "Untitled"

        val paragraphRegex = Regex("<paragraph>([\\s\\S]*?)</paragraph>")
        val translationRegex = Regex("<translation>([\\s\\S]*?)</translation>")

        val paragraphs = paragraphRegex.findAll(content).map { it.groupValues[1].trim() }.toList()
        val translations = translationRegex.findAll(content).map { it.groupValues[1].trim() }.toList()

        val result = paragraphs.mapIndexed { index, englishText ->
            val translation = translations.getOrElse(index) { "" }
            ArticleParagraph(
                orderIndex = index + 1,
                englishText = englishText,
                chineseTranslation = translation
            )
        }

        return Pair(title, result)
    }
}
