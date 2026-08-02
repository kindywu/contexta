package com.ak.contexta.data.repository

import com.ak.contexta.data.local.dao.ArticleBatchDao
import com.ak.contexta.data.local.dao.ArticleDao
import com.ak.contexta.data.local.dao.ArticleParagraphDao
import com.ak.contexta.data.local.dao.DailyLearningDao
import com.ak.contexta.data.local.dao.GenerationErrorLogDao
import com.ak.contexta.data.local.dao.GenerationErrorWithStatus
import com.ak.contexta.data.local.dao.GenerationPipelineStatusDao
import com.ak.contexta.data.local.entity.ArticleBatchEntity
import com.ak.contexta.data.local.entity.ArticleEntity
import com.ak.contexta.data.local.entity.ArticleParagraphEntity
import com.ak.contexta.data.local.entity.DailyLearningEntity
import com.ak.contexta.data.local.entity.GenerationErrorLogEntity
import com.ak.contexta.domain.model.Article
import com.ak.contexta.domain.model.ArticleParagraph
import com.ak.contexta.domain.model.ArticleStatus
import com.ak.contexta.domain.model.BatchStatus
import com.ak.contexta.domain.model.DailyLearningInfo
import com.ak.contexta.domain.model.GenerationError
import com.ak.contexta.domain.model.ArticleBatch as ArticleBatchModel
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.time.TimeProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ArticleRepositoryImpl @Inject constructor(
    private val batchDao: ArticleBatchDao,
    private val articleDao: ArticleDao,
    private val paragraphDao: ArticleParagraphDao,
    private val pipelineStatusDao: GenerationPipelineStatusDao,
    private val errorLogDao: GenerationErrorLogDao,
    private val dailyLearningDao: DailyLearningDao,
    private val timeProvider: TimeProvider
) : ArticleRepository {

    override suspend fun findNextReadyBatch(difficulty: String, afterDate: String?): ArticleBatchModel? =
        batchDao.findNextReadyBatch(difficulty, afterDate)?.toModel()

    override suspend fun getUnassignedReadyBatches(difficulty: String, minGeneratedOn: String?): List<ArticleBatchModel> {
        val date = minGeneratedOn ?: timeProvider.todayDateString()
        return batchDao.getUnassignedReadyBatches(difficulty, date).map { it.toModel() }
    }

    override suspend fun getAssignedBatchForDate(readDate: String): ArticleBatchModel? {
        val dailyLearning = dailyLearningDao.getByLearningDate(readDate) ?: return null
        return batchDao.getById(dailyLearning.refBatchId)?.toModel()
    }

    override suspend fun getAllDailyLearningInfos(): List<DailyLearningInfo> {
        val allReads = dailyLearningDao.getAll()
        return allReads.mapNotNull { read ->
            val batch = batchDao.getById(read.refBatchId)?.toModel() ?: return@mapNotNull null
            DailyLearningInfo(
                learningDate = read.learningDate,
                dailyCountSnapshot = read.dailyCountSnapshot,
                batch = batch
            )
        }
    }

    override suspend fun getMaxRefBatchDate(): String? =
        dailyLearningDao.getMaxRefBatchDate()

    override suspend fun getBatchById(batchId: Long): ArticleBatchModel? =
        batchDao.getById(batchId)?.toModel()

    override suspend fun assignBatchForToday(batchId: Long, refBatchDate: String, dailyCount: Int): Boolean {
        val today = timeProvider.todayDateString()
        // Check if today already has a daily_learning record
        val existing = dailyLearningDao.getByLearningDate(today)
        if (existing != null) return false

        dailyLearningDao.insert(
            DailyLearningEntity(
                learningDate = today,
                refBatchDate = refBatchDate,
                refBatchId = batchId,
                dailyCountSnapshot = dailyCount
            )
        )
        return true
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
        difficulty: String,
        generatedOn: String?
    ): Long {
        val date = generatedOn ?: timeProvider.todayDateString()
        val entity = ArticleBatchEntity(
            status = "PENDING",
            difficultyLevelSnapshot = difficulty,
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
        val now = timeProvider.nowDateTimeString()
        return batchDao.claimForGeneration(batchId, now) > 0
    }

    override suspend fun claimArticle(articleId: Long): Boolean {
        val now = timeProvider.nowDateTimeString()
        return articleDao.claimForGeneration(articleId, now) > 0
    }

    override suspend fun completeArticle(
        articleId: Long,
        title: String,
        paragraphs: List<ArticleParagraph>,
        retryCount: Int
    ) {
        val now = timeProvider.nowDateTimeString()
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
        batchDao.updateStatus(batchId, "READY", timeProvider.nowDateTimeString())
    }

    override suspend fun markBatchBlocked(batchId: Long, reason: String, appVersionCode: Int): Long? {
        val now = timeProvider.nowDateTimeString()
        batchDao.markBlocked(batchId = batchId, reason = reason, now = now)
        // 批次错误详情写入流水账，pipeline_status 只保留全局开关
        val errorLogId = errorLogDao.insert(
            GenerationErrorLogEntity(
                entityType = "BATCH",
                entityId = batchId,
                errorCode = "STRUCTURAL_PIPELINE_BLOCKED",
                errorMessage = reason,
                createdAt = now
            )
        )
        pipelineStatusDao.setBlocked(reason, now, appVersionCode)
        return errorLogId
    }

    override suspend fun failArticle(
        articleId: Long,
        status: String,
        errorCode: String?,
        errorMessage: String?,
        errorHelp: String?,
        retryCount: Int
    ): Long? {
        val now = timeProvider.nowDateTimeString()
        articleDao.updateStatusWithRetryTime(articleId, status, now)
        return if (errorCode != null || errorMessage != null) {
            errorLogDao.insert(
                GenerationErrorLogEntity(
                    entityType = "ARTICLE",
                    entityId = articleId,
                    errorCode = errorCode ?: "UNKNOWN",
                    errorMessage = errorMessage ?: "未知错误",
                    errorHelp = errorHelp,
                    retryCount = retryCount,
                    createdAt = now
                )
            )
        } else null
    }

    override suspend fun fatalArticle(
        articleId: Long,
        errorCode: String?,
        errorMessage: String?,
        retryCount: Int
    ): Long? {
        val now = timeProvider.nowDateTimeString()
        articleDao.updateStatusWithRetryTime(articleId, "FATAL", now)
        return if (errorCode != null || errorMessage != null) {
            errorLogDao.insert(
                GenerationErrorLogEntity(
                    entityType = "ARTICLE",
                    entityId = articleId,
                    errorCode = errorCode ?: "UNKNOWN",
                    errorMessage = errorMessage ?: "未知错误",
                    retryCount = retryCount,
                    createdAt = now
                )
            )
        } else null
    }

    override suspend fun markErrorNotified(errorLogId: Long) {
        errorLogDao.markNotified(errorLogId, timeProvider.nowMillis())
    }

    override suspend fun markBatchReadyNotified(batchId: Long) {
        batchDao.markReadyNotified(batchId, timeProvider.nowMillis())
    }

    override suspend fun getUnnotifiedErrors(createdAfter: String): List<GenerationError> =
        errorLogDao.getUnnotified(createdAfter).map { entity ->
            GenerationError(
                id = entity.id,
                entityId = entity.entityId,
                entityType = entity.entityType,
                errorCode = entity.errorCode,
                errorMessage = entity.errorMessage,
                errorHelp = entity.errorHelp,
                retryCount = entity.retryCount,
                createdAt = entity.createdAt
            )
        }

    override suspend fun getReadyBatchesUnnotified(): List<ArticleBatchModel> =
        batchDao.getReadyUnnotified().map { it.toModel() }

    override suspend fun addReadSeconds(articleId: Long, deltaSeconds: Int) {
        articleDao.addReadSeconds(articleId, deltaSeconds)
    }

    override suspend fun tryMarkReadCompleted(articleId: Long) {
        articleDao.markReadCompleted(articleId, timeProvider.nowDateTimeString())
    }

    override suspend fun forceMarkReadCompleted(articleId: Long) {
        articleDao.forceMarkReadCompleted(articleId, timeProvider.nowDateTimeString())
    }

    override suspend fun reconcileOrphanArticles() {
        // 重置所有 GENERATING 文章回 PENDING。
        // 同时重置 TIMEOUT / FAILED 文章 —— 这些可能是上一次超时
        // 导致协程取消而遗留的孤儿状态。
        // 同时重置 GENERATING 批次回 PENDING —— 使 Worker 可以重新 claim。
        // Worker 的 claimArticle() 有 CAS 保护（只认 PENDING/TIMEOUT/FAILED），
        // 即使 batch 仍在处理中，worker 会重新 claim，不会重复生成。
        articleDao.resetAllGenerating()
        articleDao.resetAllTimedOutAndFailed()
        batchDao.resetAllGeneratingBatches()
    }

    override suspend fun getGeneratingBatches(): List<ArticleBatchModel> =
        batchDao.getGeneratingBatches().map { it.toModel() }

    override fun observeArticles(batchId: Long): Flow<List<Article>> =
        articleDao.observeByBatch(batchId).map { list -> list.map { it.toModel() } }

    override suspend fun getArticle(articleId: Long): Article? =
        articleDao.getById(articleId)?.toModel()?.let { article ->
            val paragraphs = paragraphDao.getByArticle(articleId).map { p ->
                ArticleParagraph(p.orderIndex, p.englishText, p.chineseTranslation)
            }
            article.copy(paragraphs = paragraphs)
        }

    override fun observeGenerationErrors(): Flow<List<GenerationError>> =
        errorLogDao.observeArticleErrors().map { list -> list.map { it.toModel() } }

    override suspend fun resetArticleForRetry(articleId: Long) {
        articleDao.resetForRetry(articleId)
    }

    override suspend fun getBatchByDifficultyAndDate(
        difficulty: String,
        date: String
    ): ArticleBatchModel? =
        batchDao.getByDifficultyAndDate(difficulty, date)?.toModel()

    // ─── Mapping helpers ───

    private fun ArticleBatchEntity.toModel() = ArticleBatchModel(
        id = id,
        status = BatchStatus.from(status),
        difficultyLevelSnapshot = difficultyLevelSnapshot,
        generatedOn = generatedOn,
        lastUpdatedAt = lastUpdatedAt,
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
        maxRetries = maxRetries,
        nextRetryAt = nextRetryAt
    )

    private fun GenerationErrorWithStatus.toModel() = GenerationError(
        id = error.id,
        entityId = error.entityId,
        entityType = error.entityType,
        errorCode = error.errorCode,
        errorMessage = error.errorMessage,
        errorHelp = error.errorHelp,
        retryCount = error.retryCount,
        createdAt = error.createdAt,
        status = articleStatus
    )
}
