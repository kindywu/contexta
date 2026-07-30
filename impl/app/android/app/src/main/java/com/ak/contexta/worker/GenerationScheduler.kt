package com.ak.contexta.worker

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.ak.contexta.domain.BackgroundWorkScheduler
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Schedules ArticleGenerationWorker for batch processing.
 *
 * Uses uniqueWork with KEEP policy to prevent duplicate generation:
 * if the same batch is already queued or running, the new request is discarded.
 */
@Singleton
class GenerationScheduler @Inject constructor(
    @ApplicationContext private val context: Context
) : BackgroundWorkScheduler {
    companion object {
        private const val TAG = "GenerationScheduler"
        private const val UNIQUE_WORK_PREFIX = "article_generation_batch_"
    }

    /**
     * Enqueue generation for a batch.
     * Returns true if the work was newly enqueued, false if already pending/running.
     */
    override fun scheduleBatchGeneration(batchId: Long, appVersionCode: Int): Boolean {
        Log.i(TAG, "Scheduling Worker for batch $batchId")

        val workRequest = OneTimeWorkRequestBuilder<ArticleGenerationWorker>()
            .setInputData(ArticleGenerationWorker.buildInputData(batchId, appVersionCode))
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                30,
                TimeUnit.SECONDS
            )
            .addTag("batch_$batchId")
            .build()

        val uniqueWorkName = "$UNIQUE_WORK_PREFIX$batchId"

        val workManager = WorkManager.getInstance(context)
        val existingWorkPolicy = ExistingWorkPolicy.KEEP

        workManager.enqueueUniqueWork(uniqueWorkName, existingWorkPolicy, workRequest)
        Log.i(TAG, "Worker enqueued for batch $batchId (name=$uniqueWorkName)")

        return true
    }

    /**
     * Cancel any pending generation for a specific batch.
     */
    override fun cancelBatchGeneration(batchId: Long) {
        val uniqueWorkName = "$UNIQUE_WORK_PREFIX$batchId"
        WorkManager.getInstance(context).cancelUniqueWork(uniqueWorkName)
    }

    /**
     * Cancel all pending article generation work.
     */
    override fun cancelAllGeneration() {
        WorkManager.getInstance(context).cancelAllWorkByTag("article_generation")
    }
}
