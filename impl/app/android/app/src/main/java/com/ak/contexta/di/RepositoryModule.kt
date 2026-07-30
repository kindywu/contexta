package com.ak.contexta.di

import com.ak.contexta.data.repository.ArticleRepositoryImpl
import com.ak.contexta.data.repository.SettingsRepositoryImpl
import com.ak.contexta.data.repository.StatsRepositoryImpl
import com.ak.contexta.data.repository.VocabularyRepositoryImpl
import com.ak.contexta.data.repository.WordRepositoryImpl
import com.ak.contexta.domain.repository.ArticleRepository
import com.ak.contexta.domain.repository.SettingsRepository
import com.ak.contexta.domain.repository.StatsRepository
import com.ak.contexta.domain.repository.VocabularyRepository
import com.ak.contexta.domain.repository.WordRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {
    @Binds abstract fun bindArticleRepository(impl: ArticleRepositoryImpl): ArticleRepository
    @Binds abstract fun bindSettingsRepository(impl: SettingsRepositoryImpl): SettingsRepository
    @Binds abstract fun bindStatsRepository(impl: StatsRepositoryImpl): StatsRepository
    @Binds abstract fun bindVocabularyRepository(impl: VocabularyRepositoryImpl): VocabularyRepository
    @Binds abstract fun bindWordRepository(impl: WordRepositoryImpl): WordRepository
}
