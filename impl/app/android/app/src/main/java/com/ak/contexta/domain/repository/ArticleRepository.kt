package com.ak.contexta.domain.repository

import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleBatch
import com.ak.contexta.domain.model.ArticleParagraph
import kotlinx.coroutines.flow.Flow

interface ArticleRepository {
    fun observeCurrentBatch(): Flow<ArticleBatch?>
    fun observeNextBatch(): Flow<ArticleBatch?>
    fun observeExpiredBatches(): Flow<List<ArticleBatch>>

    suspend fun getCurrentBatch(): ArticleBatch?
    suspend fun getNextBatch(): ArticleBatch?
    suspend fun getExpiredBatches(): List<ArticleBatch>

    fun observeArticles(batchId: Long): Flow<List<Article>>

    suspend fun getArticle(articleId: Long): Article?

    /** Check if pipeline is globally blocked */
    suspend fun isPipelineBlocked(): Boolean

    /** Check and recover blocked pipeline if app version is newer */
    suspend fun recoverIfNewerVersion(currentVersionCode: Int): Boolean

    /** Create a new batch (PENDING) */
    suspend fun createBatch(batchType: String, difficulty: String, dailyCount: Int): Long

    /** Create article rows (PENDING) for a batch */
    suspend fun createArticles(batchId: Long, categories: List<String>)

    /** Get articles in a batch (suspend, for workers) */
    suspend fun getArticles(batchId: Long): List<Article>

    /** Try to claim the batch for generation (CAS) */
    suspend fun claimBatch(batchId: Long): Boolean

    /** Try to claim an article for generation (CAS) */
    suspend fun claimArticle(articleId: Long): Boolean

    /** Mark article as SUCCESS and write paragraphs */
    suspend fun completeArticle(
        articleId: Long,
        title: String,
        paragraphs: List<ArticleParagraph>,
        retryCount: Int
    )

    /** Check if all articles in a batch are SUCCESS */
    suspend fun isBatchComplete(batchId: Long): Boolean

    /** Check if any article in a batch is FATAL */
    suspend fun hasFatalArticle(batchId: Long): Boolean

    /** Mark batch as READY */
    suspend fun markBatchReady(batchId: Long)

    /** Mark batch as BLOCKED */
    suspend fun markBatchBlocked(batchId: Long, reason: String, appVersionCode: Int)

    /** Promote next to current */
    suspend fun promoteNextToCurrent(nextBatchId: Long)

    /** Mark article as FAILED or TIMEOUT with optional error context */
    suspend fun failArticle(
        articleId: Long,
        status: String,
        errorCode: String? = null,
        errorMessage: String? = null,
        errorHelp: String? = null
    )

    /** Mark article as FATAL with optional error context */
    suspend fun fatalArticle(
        articleId: Long,
        errorCode: String? = null,
        errorMessage: String? = null
    )

    /** Add reading seconds */
    suspend fun addReadSeconds(articleId: Long, deltaSeconds: Int)

    /** Attempt marking read completed (only if accumulated >= 120s and not yet marked) */
    suspend fun tryMarkReadCompleted(articleId: Long)

    /** Force marking read completed regardless of accumulated time. */
    suspend fun forceMarkReadCompleted(articleId: Long)

    /** Reset orphan GENERATING articles during app startup reconciliation */
    suspend fun reconcileOrphanArticles()

    /** Observe articles with generation errors (error_code IS NOT NULL) across current batches */
    fun observeGenerationErrors(): Flow<List<Article>>

    /** Clear error state and reset article to PENDING for manual retry */
    suspend fun resetArticleForRetry(articleId: Long)
}
