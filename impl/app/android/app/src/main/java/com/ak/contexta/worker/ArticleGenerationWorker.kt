package com.ak.contexta.worker

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.ak.contexta.domain.error.PipelineBlockingException
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.usecase.GenerateArticlesUseCase
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

/**
 * 文章生成 Worker。
 * 薄层：只做批次 CAS 抢占 + 调 Use Case + WorkManager 结果映射。
 * 所有业务逻辑和错误处理在 [GenerateArticlesUseCase] 中。
 */
@HiltWorker
class ArticleGenerationWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val articleRepository: ArticleRepository,
    private val generateArticles: GenerateArticlesUseCase
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

        // CAS claim the batch
        if (!articleRepository.claimBatch(batchId)) {
            Log.w(TAG, "Batch $batchId claim failed (already claimed or terminal)")
            return Result.success()
        }
        Log.i(TAG, "Batch $batchId claimed successfully")

        return try {
            generateArticles(batchId, appVersionCode)
            Log.i(TAG, "Batch $batchId processing completed")
            Result.success()
        } catch (e: PipelineBlockingException) {
            Log.e(TAG, "Structural error for batch $batchId: ${e.message}")
            Result.failure()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error for batch $batchId: ${e.message}", e)
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        }
    }
}
