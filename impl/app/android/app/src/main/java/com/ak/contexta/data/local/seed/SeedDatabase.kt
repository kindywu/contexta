package com.ak.contexta.data.local.seed

import android.content.ContentValues
import android.content.Context
import androidx.room.OnConflictStrategy
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.ZoneId

/**
 * 首次安装时写入种子数据。
 *
 * 创建 3 个历史批次（LOW / MEDIUM / HIGH），日期固定为 2026-03-29，
 * 每个批次 5 篇已完成文章（共 15 篇），作为用户打开 app 时的初始阅读内容。
 *
 * 这些批次均为 EXPIRED（历史批次），不影响后续正常的批次生成流程。
 */
fun seedDatabase(context: Context, json: Json, db: SupportSQLiteDatabase) {
    val jsonText = context.assets.open("seed_articles.json")
        .bufferedReader()
        .use { it.readText() }
    val seedData = json.decodeFromString<SeedData>(jsonText)

    val seedDate = "2026-03-29"
    val now = System.currentTimeMillis()

    db.beginTransaction()
    try {
        val byDifficulty = seedData.seedArticles.groupBy { it.difficultyLevel }

        for ((difficulty, articles) in byDifficulty) {
            val batchValues = ContentValues().apply {
                put("batch_type", "EXPIRED")
                put("status", "EXPIRED")
                put("difficulty_level_snapshot", difficulty)
                put("daily_count_snapshot", 5)
                put("generated_on", seedDate)
                put("unlocked_on", null as String?)
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
