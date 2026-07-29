package com.ak.contexta.domain.repository

import com.ak.contexta.data.local.ContextaTypeConverters
import com.ak.contexta.data.local.dao.ArticleBatchDao
import com.ak.contexta.data.local.dao.ArticleDao
import com.ak.contexta.data.local.dao.ArticleParagraphDao
import com.ak.contexta.data.local.dao.GenerationPipelineStatusDao
import com.ak.contexta.data.local.entity.ArticleBatchEntity
import com.ak.contexta.data.local.entity.ArticleEntity
import com.ak.contexta.data.local.entity.ArticleParagraphEntity
import com.ak.contexta.data.local.entity.GenerationPipelineStatusEntity
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.model.ArticleBatch as ArticleBatchModel
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.BatchType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ArticleRepository @Inject constructor(
    private val batchDao: ArticleBatchDao,
    private val articleDao: ArticleDao,
    private val paragraphDao: ArticleParagraphDao,
    private val pipelineStatusDao: GenerationPipelineStatusDao
) {
    fun observeCurrentBatch(): Flow<ArticleBatchModel?> =
        batchDao.observeByType(BatchType.CURRENT.value).map { it?.toModel() }

    fun observeNextBatch(): Flow<ArticleBatchModel?> =
        batchDao.observeByType(BatchType.NEXT.value).map { it?.toModel() }

    suspend fun getCurrentBatch(): ArticleBatchModel? =
        batchDao.getByType(BatchType.CURRENT.value)?.toModel()

    suspend fun getNextBatch(): ArticleBatchModel? =
        batchDao.getByType(BatchType.NEXT.value)?.toModel()

    fun observeArticles(batchId: Long): Flow<List<Article>> =
        articleDao.observeByBatch(batchId).map { list -> list.map { it.toModel() } }

    suspend fun getArticle(articleId: Long): Article? =
        articleDao.getById(articleId)?.toModel()?.let { article ->
            val paragraphs = paragraphDao.getByArticle(articleId).map { p ->
                ArticleParagraph(p.orderIndex, p.englishText, p.chineseTranslation)
            }
            article.copy(paragraphs = paragraphs)
        }

    /** Check if pipeline is globally blocked */
    suspend fun isPipelineBlocked(): Boolean =
        pipelineStatusDao.get()?.isBlocked == true

    /** Check and recover blocked pipeline if app version is newer */
    suspend fun recoverIfNewerVersion(currentVersionCode: Int): Boolean {
        val status = pipelineStatusDao.get() ?: return false
        if (!status.isBlocked) return false
        val blockedVersion = status.blockedAppVersionCode ?: return false
        if (currentVersionCode > blockedVersion) {
            // Clear blocked flag and reset all FATAL articles
            pipelineStatusDao.clearBlocked()
            // Reset FATAL articles to PENDING (in all batches)
            articleDao.resetOrphanGenerating(0) // need batch-specific version
            return true
        }
        return false
    }

    /** Create a new batch (PENDING) */
    suspend fun createBatch(batchType: String, difficulty: String, dailyCount: Int): Long {
        val entity = ArticleBatchEntity(
            batchType = batchType,
            status = "PENDING",
            difficultyLevelSnapshot = difficulty,
            dailyCountSnapshot = dailyCount,
            generatedOn = ContextaTypeConverters.currentDateString()
        )
        return batchDao.insert(entity)
    }

    /** Create article rows (PENDING) for a batch */
    suspend fun createArticles(batchId: Long, categories: List<String>) {
        val articles = categories.mapIndexed { index, category ->
            ArticleEntity(
                batchId = batchId,
                orderIndex = index + 1,
                contentCategory = category
            )
        }
        articleDao.insertAll(articles)
    }

    /** Get articles in a batch (suspend, for workers) */
    suspend fun getArticles(batchId: Long): List<Article> =
        articleDao.getByBatch(batchId).map { it.toModel() }

    /** Try to claim the batch for generation (CAS) */
    suspend fun claimBatch(batchId: Long): Boolean {
        val now = System.currentTimeMillis()
        return batchDao.claimForGeneration(batchId, now) > 0
    }

    /** Try to claim an article for generation (CAS) */
    suspend fun claimArticle(articleId: Long): Boolean {
        val now = System.currentTimeMillis()
        return articleDao.claimForGeneration(articleId, now) > 0
    }

    /** Mark article as SUCCESS and write paragraphs */
    suspend fun completeArticle(
        articleId: Long,
        title: String,
        paragraphs: List<ArticleParagraph>,
        retryCount: Int
    ) {
        val now = System.currentTimeMillis()
        // Write title + status in one step
        articleDao.markSuccess(articleId, title, retryCount, now)
        // Delete old paragraphs and insert new ones
        paragraphDao.deleteByArticle(articleId)
        val entities = paragraphs.mapIndexed { index, p ->
            ArticleParagraphEntity(
                articleId = articleId,
                orderIndex = p.orderIndex.takeIf { it > 0 } ?: (index + 1),
                englishText = p.englishText,
                chineseTranslation = p.chineseTranslation
            )
        }
        paragraphDao.insertAll(entities)
    }

    /** Check if all articles in a batch are SUCCESS */
    suspend fun isBatchComplete(batchId: Long): Boolean {
        val total = articleDao.countByBatch(batchId)
        val success = articleDao.countSuccessByBatch(batchId)
        return total > 0 && total == success
    }

    /** Check if any article in a batch is FATAL */
    suspend fun hasFatalArticle(batchId: Long): Boolean =
        articleDao.countFatalByBatch(batchId) > 0

    /** Mark batch as READY */
    suspend fun markBatchReady(batchId: Long) {
        batchDao.updateStatus(batchId, "READY", System.currentTimeMillis())
    }

    /** Mark batch as BLOCKED */
    suspend fun markBatchBlocked(batchId: Long, reason: String, appVersionCode: Int) {
        val now = System.currentTimeMillis()
        batchDao.updateStatus(batchId, "BLOCKED", now)
        pipelineStatusDao.setBlocked(reason, now, appVersionCode)
    }

    /** Promote next to current */
    suspend fun promoteNextToCurrent(nextBatchId: Long) {
        val current = batchDao.getByType(BatchType.CURRENT.value)
        val now = System.currentTimeMillis()
        val today = ContextaTypeConverters.currentDateString()

        if (current != null) {
            batchDao.expire(current.id, now)
        }
        batchDao.promoteToCurrent(nextBatchId, today, now)
    }

    /** When daily count changes: invalidate NEXT batch if it hasn't been unlocked */
    suspend fun onDailyCountChanged(oldCount: Int, newCount: Int) {
        val next = batchDao.getByType(BatchType.NEXT.value) ?: return
        if (next.status == "CURRENT") return // already promoted
        if (next.unlockedOn != null) return // can't happen for NEXT but guard
        // Invalidate and a new batch will be created
        batchDao.invalidate(next.id, System.currentTimeMillis())

        // Do not create a new batch here — the GenerationManager handles the lifecycle
    }

    /** Mark article as FAILED or TIMEOUT */
    suspend fun failArticle(articleId: Long, status: String) {
        articleDao.updateStatus(articleId, status)
    }

    /** Mark article as FATAL */
    suspend fun fatalArticle(articleId: Long) {
        articleDao.updateStatus(articleId, "FATAL")
    }

    /** Add reading seconds */
    suspend fun addReadSeconds(articleId: Long, deltaSeconds: Int) {
        articleDao.addReadSeconds(articleId, deltaSeconds)
    }

    /** Attempt marking read completed (only if accumulated >= 120s and not yet marked) */
    suspend fun tryMarkReadCompleted(articleId: Long) {
        articleDao.markReadCompleted(articleId, System.currentTimeMillis())
    }

    /** Reset orphan GENERATING articles during app startup reconciliation */
    suspend fun reconcileOrphanArticles() {
        // Find GENERATING articles and reset based on batch status
        // This is a simplified version — a full implementation would check WorkManager state
    }

    // ─── Mapping helpers ───

    private fun ArticleBatchEntity.toModel() = ArticleBatchModel(
        id = id,
        batchType = BatchType.from(batchType),
        status = BatchStatus.from(status),
        difficultyLevelSnapshot = difficultyLevelSnapshot,
        dailyCountSnapshot = dailyCountSnapshot,
        generatedOn = generatedOn,
        unlockedOn = unlockedOn,
        lastUpdatedAt = lastUpdatedAt
    )

    private fun ArticleEntity.toModel() = Article(
        id = id,
        batchId = batchId,
        orderIndex = orderIndex,
        contentCategory = contentCategory,
        title = title,
        status = ArticleStatus.from(status),
        generationStartedAt = generationStartedAt,
        generationCompletedAt = generationCompletedAt,
        retryCount = retryCount,
        accumulatedReadSeconds = accumulatedReadSeconds,
        readCompletedAt = readCompletedAt,
        lastRetryAt = lastRetryAt
    )
}
