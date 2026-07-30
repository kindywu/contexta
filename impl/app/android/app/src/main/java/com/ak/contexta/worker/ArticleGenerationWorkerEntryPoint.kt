package com.ak.contexta.worker

import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.usecase.GenerateArticlesUseCase
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * Hilt entry point for manual ArticleGenerationWorker creation.
 * Only needed when WorkManager auto-initialization is disabled
 * and manual worker creation is used via GenerationWorkerFactory.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface ArticleGenerationWorkerEntryPoint {
    fun articleRepository(): ArticleRepository
    fun generateArticlesUseCase(): GenerateArticlesUseCase
}
