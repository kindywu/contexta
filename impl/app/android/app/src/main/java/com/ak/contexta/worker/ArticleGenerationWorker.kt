package com.ak.contexta.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.ak.contexta.R
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

        // expedited 工作的前台通知 id / channel
        private const val FOREGROUND_NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "article_generation"
        private const val CHANNEL_NAME = "文章生成"

        fun buildInputData(batchId: Long, appVersionCode: Int = 0) = workDataOf(
            KEY_BATCH_ID to batchId,
            KEY_APP_VERSION_CODE to appVersionCode
        )
    }

    /**
     * Expedited 工作的前台服务通知。
     * 以 FGS 运行可避免应用转后台时被系统（MIUI 节流/停任务）干扰。
     * 通知内容不含敏感信息，仅提示生成进行中。
     */
    override suspend fun getForegroundInfo(): ForegroundInfo {
        val batchId = inputData.getLong(KEY_BATCH_ID, -1L)
        val context = applicationContext

        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            )
        )

        val notification: Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Contexta 正在生成文章")
            .setContentText(if (batchId > 0) "批次 #$batchId 生成中…" else "生成中…")
            .setOngoing(true)
            .build()

        return ForegroundInfo(FOREGROUND_NOTIFICATION_ID, notification)
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
            val finished = generateArticles(batchId, appVersionCode)
            Log.i(TAG, "Batch $batchId processing completed (finished=$finished)")
            // 仍有未完成文章（GENERATING/TIMEOUT/FAILED）时返回 retry，
            // 让 WorkManager 在 backoff 后重新调度 Worker 继续生成。
            if (finished) Result.success() else Result.retry()
        } catch (e: PipelineBlockingException) {
            Log.e(TAG, "Structural error for batch $batchId: ${e.message}")
            Result.failure()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error for batch $batchId: ${e.message}", e)
            if (runAttemptCount < 2) Result.retry() else Result.failure()
        }
    }
}
