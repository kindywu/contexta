package com.ak.contexta.data.local.seed

import android.content.ContentValues
import android.content.Context
import androidx.room.OnConflictStrategy
import androidx.sqlite.db.SupportSQLiteDatabase
import com.ak.contexta.data.local.ContextaTypeConverters
import kotlinx.serialization.json.Json

/**
 * 首次安装时写入种子数据。
 *
 * 创建 3 个历史批次（LOW / MEDIUM / HIGH），日期固定为 2026-03-29，
 * 每个批次 5 篇已完成文章（共 15 篇），作为用户打开 app 时的初始阅读内容。
 *
 * 这些批次均为 READY（已生成完成的批次），等待 [StartupOrchestrationUseCase]
 * 在用户首次进入时将其分配到当天的 [daily_learning] 表。
 */
fun seedDatabase(context: Context, json: Json, db: SupportSQLiteDatabase) {
    val jsonText = context.assets.open("seed_articles.json")
        .bufferedReader()
        .use { it.readText() }
    val seedData = json.decodeFromString<SeedData>(jsonText)

    val seedDate = "2026-03-29"
    // 种子批次是历史数据，完成时间取固定日期（手机时区），与 generated_on 保持一致
    val now = ContextaTypeConverters.dateTimeStringAt(2026, 3, 29, 12, 0)

    db.beginTransaction()
    try {
        val byDifficulty = seedData.seedArticles.groupBy { it.difficultyLevel }

        for ((difficulty, articles) in byDifficulty) {
            val batchValues = ContentValues().apply {
                put("status", "READY")
                put("difficulty_level_snapshot", difficulty)
                put("generated_on", seedDate)
                put("last_updated_at", now)
            }
            val batchId = db.insert("article_batch", OnConflictStrategy.NONE, batchValues)
            if (batchId == -1L) {
                throw RuntimeException("Failed to insert seed batch for $difficulty")
            }

            for (article in articles.sortedBy { it.orderIndex }) {
                val articleValues = ContentValues().apply {
                    put("batch_id", batchId)
                    put("order_index", article.orderIndex)
                    put("content_category", article.contentCategory)
                    put("title", article.title)
                    put("status", "SUCCESS")
                    put("retry_count", 0)
                    put("max_retries", 3)
                    put("accumulated_read_seconds", 0)
                    put("generation_completed_at", now)
                }
                val articleId = db.insert("article", OnConflictStrategy.NONE, articleValues)
                if (articleId == -1L) {
                    throw RuntimeException("Failed to insert seed article: ${article.title}")
                }

                for (para in article.paragraphs) {
                    val paraValues = ContentValues().apply {
                        put("article_id", articleId)
                        put("order_index", para.orderIndex)
                        put("english_text", para.englishText)
                        put("chinese_translation", para.chineseTranslation)
                    }
                    db.insert("article_paragraph", OnConflictStrategy.NONE, paraValues)
                }
            }
        }

        db.setTransactionSuccessful()
    } finally {
        db.endTransaction()
    }
}
