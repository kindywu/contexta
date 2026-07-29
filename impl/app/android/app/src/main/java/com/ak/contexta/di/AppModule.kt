package com.ak.contexta.di

import android.content.Context
import androidx.room.Room
import com.ak.contexta.data.local.ContextaDatabase
import com.ak.contexta.data.local.Migrations
import com.ak.contexta.data.local.dao.ArticleBatchDao
import com.ak.contexta.data.local.dao.ArticleDao
import com.ak.contexta.data.local.dao.ArticleParagraphDao
import com.ak.contexta.data.local.dao.ConfigChangeLogDao
import com.ak.contexta.data.local.dao.DailyLearningLogDao
import com.ak.contexta.data.local.dao.ExampleSentenceDao
import com.ak.contexta.data.local.dao.GenerationPipelineStatusDao
import com.ak.contexta.data.local.dao.LearningStatsSummaryDao
import com.ak.contexta.data.local.dao.SchemaMigrationLogDao
import com.ak.contexta.data.local.dao.UserSettingsDao
import com.ak.contexta.data.local.dao.VocabularyEntryDao
import com.ak.contexta.data.local.dao.WordDao
import com.ak.contexta.data.local.dao.WordSenseDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): ContextaDatabase {
        return Room.databaseBuilder(
            context,
            ContextaDatabase::class.java,
            "contexta.db"
        )
            .addMigrations(*Migrations.ALL)
            .fallbackToDestructiveMigration() // only safe during development
            .build()
    }

    @Provides fun provideUserSettingsDao(db: ContextaDatabase): UserSettingsDao = db.userSettingsDao()
    @Provides fun provideConfigChangeLogDao(db: ContextaDatabase): ConfigChangeLogDao = db.configChangeLogDao()
    @Provides fun provideArticleBatchDao(db: ContextaDatabase): ArticleBatchDao = db.articleBatchDao()
    @Provides fun provideArticleDao(db: ContextaDatabase): ArticleDao = db.articleDao()
    @Provides fun provideArticleParagraphDao(db: ContextaDatabase): ArticleParagraphDao = db.articleParagraphDao()
    @Provides fun provideWordDao(db: ContextaDatabase): WordDao = db.wordDao()
    @Provides fun provideWordSenseDao(db: ContextaDatabase): WordSenseDao = db.wordSenseDao()
    @Provides fun provideExampleSentenceDao(db: ContextaDatabase): ExampleSentenceDao = db.exampleSentenceDao()
    @Provides fun provideVocabularyEntryDao(db: ContextaDatabase): VocabularyEntryDao = db.vocabularyEntryDao()
    @Provides fun provideDailyLearningLogDao(db: ContextaDatabase): DailyLearningLogDao = db.dailyLearningLogDao()
    @Provides fun provideLearningStatsSummaryDao(db: ContextaDatabase): LearningStatsSummaryDao = db.learningStatsSummaryDao()
    @Provides fun provideGenerationPipelineStatusDao(db: ContextaDatabase): GenerationPipelineStatusDao = db.generationPipelineStatusDao()
    @Provides fun provideSchemaMigrationLogDao(db: ContextaDatabase): SchemaMigrationLogDao = db.schemaMigrationLogDao()
}
