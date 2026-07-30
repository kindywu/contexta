package com.ak.contexta.data.local.seed

import android.content.ContentValues
import android.content.Context
import androidx.room.OnConflictStrategy
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.ZoneId

fun seedDatabase(context: Context, json: Json, db: SupportSQLiteDatabase) {
    val jsonText = context.assets.open("seed_articles.json")
        .bufferedReader()
        .use { it.readText() }
    val seedData = json.decodeFromString<SeedData>(jsonText)

    val today = LocalDate.now(ZoneId.of("Asia/Shanghai")).toString()
    val now = System.currentTimeMillis()

    db.beginTransaction()
    try {
        val batchValues = ContentValues().apply {
            put("batch_type", "CURRENT")
            put("status", "CURRENT")
            put("difficulty_level_snapshot", "SEED")
            put("daily_count_snapshot", 5)
            put("generated_on", today)
            put("unlocked_on", today)
            put("last_updated_at", now)
        }
        val batchId = db.insert("article_batch", OnConflictStrategy.NONE, batchValues)
        if (batchId == -1L) {
            throw RuntimeException("Failed to insert seed article batch")
        }

        for (article in seedData.seedArticles) {
            val articleValues = ContentValues().apply {
                put("batch_id", batchId)
                put("order_index", article.orderIndex)
                put("content_category", article.contentCategory)
                put("title", article.title)
                put("status", "SUCCESS")
                put("retry_count", 0)
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

        db.setTransactionSuccessful()
    } finally {
        db.endTransaction()
    }
}
