package com.ak.contexta.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

object Migrations {
    /**
     * Version 1 → 2: Add error fields to article table.
     */
    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE article ADD COLUMN error_code TEXT")
            db.execSQL("ALTER TABLE article ADD COLUMN error_message TEXT")
            db.execSQL("ALTER TABLE article ADD COLUMN error_help TEXT")
            db.execSQL("ALTER TABLE article ADD COLUMN max_retries INTEGER NOT NULL DEFAULT 3")
            db.execSQL("ALTER TABLE article ADD COLUMN next_retry_at INTEGER")
        }
    }

    /**
     * Version 2 → 3: Add error fields to article_batch table.
     */
    val MIGRATION_2_3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE article_batch ADD COLUMN error_code TEXT")
            db.execSQL("ALTER TABLE article_batch ADD COLUMN error_message TEXT")
            db.execSQL("ALTER TABLE article_batch ADD COLUMN blocked_reason TEXT")
            db.execSQL("ALTER TABLE article_batch ADD COLUMN blocked_at INTEGER")
        }
    }

    val ALL: Array<Migration> = arrayOf(MIGRATION_1_2, MIGRATION_2_3)
}
