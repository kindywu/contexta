package com.ak.contexta.data.repository

import com.ak.contexta.data.local.ContextaTypeConverters
import com.ak.contexta.data.local.dao.ArticleBatchDao
import com.ak.contexta.data.local.dao.ArticleDao
import com.ak.contexta.data.local.dao.ArticleParagraphDao
import com.ak.contexta.data.local.dao.GenerationPipelineStatusDao
import com.ak.contexta.data.local.entity.ArticleBatchEntity
import com.ak.contexta.data.local.entity.ArticleEntity
import com.ak.contexta.data.local.entity.ArticleParagraphEntity
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.BatchType
import com.ak.contexta.domain.model.ArticleBatch as ArticleBatchModel
import com.ak.contexta.domain.repository.ArticleRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ArticleRepositoryImpl @Inject constructor(
    private val batchDao: ArticleBatchDao,
    private val articleDao: ArticleDao,
    private val paragraphDao: ArticleParagraphDao,
    private val pipelineStatusDao: GenerationPipelineStatusDao
) : ArticleRepository {

    override fun observeCurrentBatch(): Flow<ArticleBatchModel?> =
        batchDao.observeByType(BatchType.CURRENT.value).map { it?.toModel() }

    override fun observeNextBatch(): Flow<ArticleBatchModel?> =
        batchDao.observeByType(BatchType.NEXT.value).map { it?.toModel() }

    override fun observeExpiredBatches(): Flow<List<ArticleBatchModel>> =
        batchDao.observeAllByType(BatchStatus.EXPIRED.value).map { list -> list.map { it.toModel() } }

    override suspend fun getCurrentBatch(): ArticleBatchModel? =
        batchDao.getByType(BatchType.CURRENT.value)?.toModel()

    override suspend fun getNextBatch(): ArticleBatchModel? =
        batchDao.getByType(BatchType.NEXT.value)?.toModel()

    override suspend fun getExpiredBatches(): List<ArticleBatchModel> =
        batchDao.getAllByType(BatchStatus.EXPIRED.value).map { it.toModel() }

    override fun observeArticles(batchId: Long): Flow<List<Article>> =
        articleDao.observeByBatch(batchId).map { list -> list.map { it.toModel() } }

    override suspend fun getArticle(articleId: Long): Article? =
        articleDao.getById(articleId)?.toModel()?.let { article ->
            val paragraphs = paragraphDao.getByArticle(articleId).map { p ->
                ArticleParagraph(p.orderIndex, p.englishText, p.chineseTranslation)
            }
            article.copy(paragraphs = paragraphs)
        }

    override suspend fun isPipelineBlocked(): Boolean =
        pipelineStatusDao.get()?.isBlocked == true

    override suspend fun recoverIfNewerVersion(currentVersionCode: Int): Boolean {
        val status = pipelineStatusDao.get() ?: return false
        if (!status.isBlocked) return false
        val blockedVersion = status.blockedAppVersionCode ?: return false
        if (currentVersionCode > blockedVersion) {
            pipelineStatusDao.clearBlocked()
            articleDao.resetOrphanGenerating(0)
            return true
        }
        return false
    }

    override suspend fun createBatch(
        batchType: String,
        difficulty: String,
        dailyCount: Int,
        generatedOn: String?
    ): Long {
        val date = generatedOn ?: ContextaTypeConverters.currentDateString()
        val entity = ArticleBatchEntity(
            batchType = batchType,
            status = "PENDING",
            difficultyLevelSnapshot = difficulty,
            dailyCountSnapshot = dailyCount,
            generatedOn = date
        )
        return batchDao.insert(entity)
    }

    override suspend fun createArticles(batchId: Long, categories: List<String>) {
        val articles = categories.mapIndexed { index, category ->
            ArticleEntity(
                batchId = batchId,
                orderIndex = index + 1,
                contentCategory = category
            )
        }
        articleDao.insertAll(articles)
    }

    override suspend fun getArticles(batchId: Long): List<Article> =
        articleDao.getByBatch(batchId).map { it.toModel() }

    override suspend fun claimBatch(batchId: Long): Boolean {
        val now = System.currentTimeMillis()
        return batchDao.claimForGeneration(batchId, now) > 0
    }

    override suspend fun claimArticle(articleId: Long): Boolean {
        val now = System.currentTimeMillis()
        return articleDao.claimForGeneration(articleId, now) > 0
    }

    override suspend fun completeArticle(
        articleId: Long,
        title: String,
        paragraphs: List<ArticleParagraph>,
        retryCount: Int
    ) {
        val now = System.currentTimeMillis()
        articleDao.markSuccess(articleId, title, retryCount, now)
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

    override suspend fun isBatchComplete(batchId: Long): Boolean {
        val total = articleDao.countByBatch(batchId)
        val success = articleDao.countSuccessByBatch(batchId)
        return total > 0 && total == success
    }

    override suspend fun hasFatalArticle(batchId: Long): Boolean =
        articleDao.countFatalByBatch(batchId) > 0

    override suspend fun markBatchReady(batchId: Long) {
        batchDao.updateStatus(batchId, "READY", System.currentTimeMillis())
    }

    override suspend fun markBatchBlocked(batchId: Long, reason: String, appVersionCode: Int) {
        val now = System.currentTimeMillis()
        batchDao.markBlocked(
            batchId = batchId,
            reason = reason,
            errorCode = "STRUCTURAL_PIPELINE_BLOCKED",
            errorMessage = reason,
            now = now
        )
        pipelineStatusDao.setBlocked(reason, now, appVersionCode)
    }

    override suspend fun promoteNextToCurrent(nextBatchId: Long) {
        val current = batchDao.getByType(BatchType.CURRENT.value)
        val now = System.currentTimeMillis()
        val today = ContextaTypeConverters.currentDateString()

        if (current != null) {
            batchDao.expire(current.id, now)
            batchDao.updateBatchType(current.id, "EXPIRED", now)
        }
        batchDao.updateBatchType(nextBatchId, "CURRENT", now)
        batchDao.promoteToCurrent(nextBatchId, today, now)
    }

    override suspend fun expireBatch(batchId: Long) {
        val now = System.currentTimeMillis()
        batchDao.updateStatus(batchId, "EXPIRED", now)
        batchDao.updateBatchType(batchId, "EXPIRED", now)
    }

    override suspend fun reactivateBatch(batchId: Long, dailyCount: Int) {
        val now = System.currentTimeMillis()
        batchDao.updateBatchType(batchId, "NEXT", now)
        batchDao.updateStatus(batchId, "READY", now)
        batchDao.updateDailyCountSnapshot(batchId, dailyCount, now)
    }

    override suspend fun failArticle(
        articleId: Long,
        status: String,
        errorCode: String?,
        errorMessage: String?,
        errorHelp: String?
    ) {
        val now = System.currentTimeMillis()
        if (errorCode != null || errorMessage != null) {
            articleDao.updateStatusWithError(articleId, status, errorCode, errorMessage, errorHelp, now)
        } else {
            articleDao.updateStatus(articleId, status)
        }
    }

    override suspend fun fatalArticle(
        articleId: Long,
        errorCode: String?,
        errorMessage: String?
    ) {
        val now = System.currentTimeMillis()
        if (errorCode != null || errorMessage != null) {
            articleDao.markFatal(articleId, errorCode, errorMessage, now)
        } else {
            articleDao.updateStatus(articleId, "FATAL")
        }
    }

    override suspend fun addReadSeconds(articleId: Long, deltaSeconds: Int) {
        articleDao.addReadSeconds(articleId, deltaSeconds)
    }

    override suspend fun tryMarkReadCompleted(articleId: Long) {
        articleDao.markReadCompleted(articleId, System.currentTimeMillis())
    }

    override suspend fun forceMarkReadCompleted(articleId: Long) {
        articleDao.forceMarkReadCompleted(articleId, System.currentTimeMillis())
    }

    override suspend fun reconcileOrphanArticles() {
        // 重置所有 GENERATING 文章回 PENDING。
        // Worker 的 claimArticle() 有 CAS 保护（只认 PENDING/TIMEOUT/FAILED），
        // 即使 batch 仍在处理中，worker 会重新 claim，不会重复生成。
        articleDao.resetAllGenerating()
    }

    override fun observeGenerationErrors(): Flow<List<Article>> =
        articleDao.observeGenerationErrors().map { list -> list.map { it.toModel() } }

    override suspend fun resetArticleForRetry(articleId: Long) {
        articleDao.resetForRetry(articleId)
    }

    // ─── Mapping helpers ───

    override suspend fun getBatchByDifficultyAndDate(
        difficulty: String,
        date: String
    ): ArticleBatchModel? =
        batchDao.getByDifficultyAndDate(difficulty, date)?.toModel()

    private fun ArticleBatchEntity.toModel() = ArticleBatchModel(
        id = id,
        batchType = BatchType.from(batchType),
        status = BatchStatus.from(status),
        difficultyLevelSnapshot = difficultyLevelSnapshot,
        dailyCountSnapshot = dailyCountSnapshot,
        generatedOn = generatedOn,
        unlockedOn = unlockedOn,
        lastUpdatedAt = lastUpdatedAt,
        errorCode = errorCode,
        errorMessage = errorMessage,
        blockedReason = blockedReason,
        blockedAt = blockedAt
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
        lastRetryAt = lastRetryAt,
        errorCode = errorCode,
        errorMessage = errorMessage,
        errorHelp = errorHelp,
        maxRetries = maxRetries,
        nextRetryAt = nextRetryAt
    )
}
