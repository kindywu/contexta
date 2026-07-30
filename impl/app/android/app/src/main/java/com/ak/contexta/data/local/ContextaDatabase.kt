package com.ak.contexta.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
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
import com.ak.contexta.data.local.entity.ArticleBatchEntity
import com.ak.contexta.data.local.entity.ArticleEntity
import com.ak.contexta.data.local.entity.ArticleParagraphEntity
import com.ak.contexta.data.local.entity.ConfigChangeLogEntity
import com.ak.contexta.data.local.entity.DailyLearningLogEntity
import com.ak.contexta.data.local.entity.ExampleSentenceEntity
import com.ak.contexta.data.local.entity.GenerationPipelineStatusEntity
import com.ak.contexta.data.local.entity.LearningStatsSummaryEntity
import com.ak.contexta.data.local.entity.SchemaMigrationLogEntity
import com.ak.contexta.data.local.entity.UserSettingsEntity
import com.ak.contexta.data.local.entity.VocabularyEntryEntity
import com.ak.contexta.data.local.entity.WordEntity
import com.ak.contexta.data.local.entity.WordSenseEntity

@Database(
    version = 1,
    entities = [
        UserSettingsEntity::class,
        ConfigChangeLogEntity::class,
        ArticleBatchEntity::class,
        ArticleEntity::class,
        ArticleParagraphEntity::class,
        WordEntity::class,
        WordSenseEntity::class,
        ExampleSentenceEntity::class,
        VocabularyEntryEntity::class,
        DailyLearningLogEntity::class,
        LearningStatsSummaryEntity::class,
        GenerationPipelineStatusEntity::class,
        SchemaMigrationLogEntity::class
    ]
)
abstract class ContextaDatabase : RoomDatabase() {
    abstract fun userSettingsDao(): UserSettingsDao
    abstract fun configChangeLogDao(): ConfigChangeLogDao
    abstract fun articleBatchDao(): ArticleBatchDao
    abstract fun articleDao(): ArticleDao
    abstract fun articleParagraphDao(): ArticleParagraphDao
    abstract fun wordDao(): WordDao
    abstract fun wordSenseDao(): WordSenseDao
    abstract fun exampleSentenceDao(): ExampleSentenceDao
    abstract fun vocabularyEntryDao(): VocabularyEntryDao
    abstract fun dailyLearningLogDao(): DailyLearningLogDao
    abstract fun learningStatsSummaryDao(): LearningStatsSummaryDao
    abstract fun generationPipelineStatusDao(): GenerationPipelineStatusDao
    abstract fun schemaMigrationLogDao(): SchemaMigrationLogDao
}
