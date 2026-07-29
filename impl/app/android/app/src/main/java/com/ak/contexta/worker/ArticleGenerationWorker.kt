package com.ak.contexta.worker

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.ak.contexta.data.remote.LlmCaller
import com.ak.contexta.data.remote.LlmFatalException
import com.ak.contexta.data.remote.LlmRecoverableExhaustedException
import com.ak.contexta.domain.PipelineBlockingException
import com.ak.contexta.domain.generation.buildArticleSystemPrompt
import com.ak.contexta.domain.generation.buildArticleUserPrompt
import com.ak.contexta.domain.generation.categoryToDifficulty
import com.ak.contexta.domain.generation.parseArticleLlmResponse
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
        private const val TAG = "ArticleGenWorker"
        private const val KEY_BATCH_ID = "batchId"
        private const val KEY_APP_VERSION_CODE = "appVersionCode"

        fun buildInputData(batchId: Long, appVersionCode: Int = 0) = workDataOf(
            KEY_BATCH_ID to batchId,
            KEY_APP_VERSION_CODE to appVersionCode
        )
    }

    override suspend fun doWork(): Result {
        val batchId = inputData.getLong(KEY_BATCH_ID, -1L)
        if (batchId == -1L) {
            Log.e(TAG, "No batchId in input data")
            return Result.failure()
        }

        val appVersionCode = inputData.getInt(KEY_APP_VERSION_CODE, 0)
        Log.i(TAG, "doWork: batchId=$batchId, runAttempt=$runAttemptCount")

        // 1. CAS claim the batch
        if (!articleRepository.claimBatch(batchId)) {
            Log.w(TAG, "Batch $batchId claim failed (already claimed or terminal)")
            // Another worker already claimed this batch — it's being processed
            // or the batch is in a terminal state
            return Result.success()
        }
        Log.i(TAG, "Batch $batchId claimed successfully")

        return try {
            processBatch(batchId, appVersionCode)
            Log.i(TAG, "Batch $batchId processing completed")
            Result.success()
        } catch (e: PipelineBlockingException) {
            Log.e(TAG, "Pipeline blocking exception for batch $batchId: ${e.message}")
            // Structural error — block the pipeline
            articleRepository.markBatchBlocked(batchId, e.message ?: "Unknown", appVersionCode)
            Result.failure()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error for batch $batchId: ${e.message}", e)
            // Unexpected error — worker will retry based on WorkManager backoff
            if (runAttemptCount < 2) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }

    private suspend fun processBatch(batchId: Long, appVersionCode: Int) {
        Log.i(TAG, "processBatch: batchId=$batchId")

        // Get articles for this batch
        val articles = articleRepository.getArticles(batchId)
        Log.i(TAG, "Found ${articles.size} articles in batch $batchId")
        if (articles.isEmpty()) {
            articleRepository.markBatchReady(batchId)
            Log.i(TAG, "Batch $batchId empty, marked ready")
            return
        }

        for (article in articles) {
            // Skip already completed articles
            if (article.status.name == "SUCCESS") {
                Log.i(TAG, "Article ${article.id} already SUCCESS, skipping")
                continue
            }

            // CAS claim the article
            if (!articleRepository.claimArticle(article.id)) {
                Log.w(TAG, "Article ${article.id} claim failed, skipping")
                continue
            }

            try {
                // Generate article via LLM
                val difficulty = categoryToDifficulty(article.contentCategory)
                Log.i(TAG, "Generating article ${article.id} (${article.contentCategory}) via LLM")
                val result = llmCaller.call(
                    buildArticleSystemPrompt(difficulty),
                    buildArticleUserPrompt(article.contentCategory, article.orderIndex)
                )

                // Parse LLM response
                val (title, paragraphs) = parseArticleLlmResponse(result.content)
                Log.i(TAG, "Article ${article.id} generated: title='$title', ${paragraphs.size} paragraphs")

                // Write to DB
                articleRepository.completeArticle(
                    articleId = article.id,
                    title = title,
                    paragraphs = paragraphs,
                    retryCount = result.retryCount
                )

            } catch (e: LlmFatalException) {
                Log.e(TAG, "Fatal LLM error for article ${article.id}: ${e.message}")
                // Non-recoverable — mark as FATAL so user can retry
                articleRepository.fatalArticle(article.id)
                // Continue with other articles
                continue

            } catch (e: LlmRecoverableExhaustedException) {
                Log.w(TAG, "Recoverable exhaustion for article ${article.id}: ${e.message}")
                // All retries exhausted — mark as FAILED for later retry
                articleRepository.failArticle(article.id, "FAILED")
                continue

            } catch (e: PipelineBlockingException) {
                Log.e(TAG, "Pipeline blocking for article ${article.id}: ${e.message}")
                // Structural — rethrow to block the batch
                articleRepository.fatalArticle(article.id)
                throw e

            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error for article ${article.id}: ${e.message}", e)
                // Unexpected — mark as TIMEOUT for later retry
                articleRepository.failArticle(article.id, "TIMEOUT")
                continue
            }
        }

        // Check batch completion
        when {
            articleRepository.hasFatalArticle(batchId) -> {
                Log.w(TAG, "Batch $batchId has FATAL articles, leaving as GENERATING")
                // At least one FATAL — leave as GENERATING; user needs to address
                // (Don't mark blocked unless it's structural)
            }
            articleRepository.isBatchComplete(batchId) -> {
                Log.i(TAG, "Batch $batchId complete, marking READY")
                articleRepository.markBatchReady(batchId)
            }
            else -> {
                Log.w(TAG, "Batch $batchId partially complete, leaving for retry")
                // Some articles failed but none FATAL — leave for retry
            }
        }
    }

}
