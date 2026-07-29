package com.ak.contexta.worker

import android.content.Context
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import dagger.hilt.android.EntryPointAccessors
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Hilt-compatible WorkerFactory for ArticleGenerationWorker.
 *
 * Note: With @HiltWorker + hilt-work, this factory is NOT needed in most cases.
 * The @HiltWorker annotation and Hilt's WorkManagerInitializer handle injection
 * automatically. This factory is provided as a fallback for manual initialization
 * if the auto-initialization is disabled in AndroidManifest.xml.
 *
 * To use it, override the default WorkManager configuration in ContextaApplication:
 *
 * ```kotlin
 * override fun onCreate() {
 *     super.onCreate()
 *     WorkManager.initialize(this, Configuration.Builder()
 *         .setWorkerFactory(GenerationWorkerFactory())
 *         .build())
 * }
 * ```
 */
@Singleton
class GenerationWorkerFactory @Inject constructor() {

    /**
     * Create an ArticleGenerationWorker instance.
     * This is used by the WorkManager configuration when auto-init is disabled.
     */
    fun createWorker(
        appContext: Context,
        workerParams: WorkerParameters
    ): ListenableWorker {
        val entryPoint = EntryPointAccessors.fromApplication(
            appContext,
            ArticleGenerationWorkerEntryPoint::class.java
        )
        return ArticleGenerationWorker(
            appContext,
            workerParams,
            entryPoint.articleRepository(),
            entryPoint.llmCaller()
        )
    }
}
