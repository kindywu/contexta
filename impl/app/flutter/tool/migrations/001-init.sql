-- 001-init.sql —— 0→1 init 脚本：v1 标准结构（17 张表 + 索引）
--
-- 版本链条起点：001 将「无版本库」（版本 0：无 db_version 表/行的库，
-- 含空库）升到 v1。之后的结构升级走 002、003、……，链条完整：
--   001-init(0→1) → 002(1→2) → 003(2→3) → …
-- 未来发布 v5 app 时遇到 v3 用户库，migrate_db.sh 按序应用 004、005。
--
-- 与 drift lib/data/local/database.g.dart（createAll）的 onUpgrade 000 镜像同步。
--
-- ⚠️ 幂等契约：全部 CREATE ... IF NOT EXISTS——对空库（全新 init）、
--    Room 遗留库（已有 15 张业务表，IF NOT EXISTS 跳过）、任意已有库
--    重复执行均安全。列级差异（如遗留库缺列）由开发期临时补丁承担
--    （/tmp，不入仓库），本脚本只描述 v1 标准结构。
--
-- ⚠️ 生命周期：开发期（tool/db_version = 0）v1 结构变更时**同步更新本文件**
--    （001 描述的 v1 = 当前开发结构）；首次发布 v1（文件改 1）后**冻结**，
--    之后的结构变更写 002 起，不得再改 001。

BEGIN IMMEDIATE;

-- ── 版本指针表（单例行 id=1，版本推进由迁移脚本收尾段管理）────────
CREATE TABLE IF NOT EXISTS `db_version` (
  `id` INTEGER NOT NULL PRIMARY KEY,
  `version` INTEGER NOT NULL,
  `updated_at` INTEGER NOT NULL
);

-- ── 迁移历史账本（每次迁移 INSERT 一条 0→N 记录）──────────────────
CREATE TABLE IF NOT EXISTS `schema_migration_log` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `from_version` INTEGER NOT NULL,
  `to_version` INTEGER NOT NULL,
  `description` TEXT NOT NULL,
  `created_at` TEXT NOT NULL
);

-- ── 基础表组 ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `user_settings` (
  `id` INTEGER NOT NULL PRIMARY KEY,
  `is_onboarded` INTEGER NOT NULL,
  `difficulty_level` TEXT NOT NULL,
  `daily_article_count` INTEGER NOT NULL,
  `translation_display_mode` TEXT NOT NULL,
  `mastery_threshold_n` INTEGER NOT NULL,
  `auto_play_audio` INTEGER NOT NULL,
  `tts_speed` REAL NOT NULL,
  `tts_voice_id` TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS `config_change_log` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `field_name` TEXT NOT NULL,
  `old_value` TEXT NOT NULL,
  `new_value` TEXT NOT NULL,
  `created_at` TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS `generation_pipeline_status` (
  `id` INTEGER NOT NULL,
  `is_blocked` INTEGER NOT NULL,
  `blocked_reason` TEXT,
  `blocked_at` TEXT,
  `blocked_app_version_code` INTEGER,
  PRIMARY KEY(`id`)
);

CREATE TABLE IF NOT EXISTS `daily_learning_log` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `log_date` TEXT NOT NULL,
  `articles_read` INTEGER NOT NULL,
  `words_added` INTEGER NOT NULL,
  `seconds_spent` INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS `learning_stats_summary` (
  `id` INTEGER NOT NULL,
  `total_articles_read` INTEGER NOT NULL,
  `total_words_added` INTEGER NOT NULL,
  `total_words_mastered` INTEGER NOT NULL,
  `total_learning_days` INTEGER NOT NULL,
  `current_streak` INTEGER NOT NULL,
  `longest_streak` INTEGER NOT NULL,
  `last_active_date` TEXT,
  PRIMARY KEY(`id`)
);

-- ── 文章表组 ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `article_batch` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `status` TEXT NOT NULL,
  `difficulty_level_snapshot` TEXT NOT NULL,
  `generated_on` TEXT NOT NULL,
  `last_updated_at` TEXT NOT NULL,
  `blocked_reason` TEXT,
  `blocked_at` TEXT,
  `ready_notified_at` INTEGER
);

CREATE TABLE IF NOT EXISTS `article` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `batch_id` INTEGER NOT NULL,
  `order_index` INTEGER NOT NULL,
  `content_category` TEXT NOT NULL,
  `title` TEXT,
  `status` TEXT NOT NULL,
  `generation_started_at` TEXT,
  `generation_completed_at` TEXT,
  `retry_count` INTEGER NOT NULL,
  `accumulated_read_seconds` INTEGER NOT NULL,
  `read_completed_at` TEXT,
  `last_retry_at` TEXT,
  `max_retries` INTEGER NOT NULL,
  `next_retry_at` TEXT,
  FOREIGN KEY(`batch_id`) REFERENCES `article_batch`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `article_paragraph` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `article_id` INTEGER NOT NULL,
  `order_index` INTEGER NOT NULL,
  `english_text` TEXT NOT NULL,
  `chinese_translation` TEXT NOT NULL,
  FOREIGN KEY(`article_id`) REFERENCES `article`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `generation_error_log` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `entity_type` TEXT NOT NULL,
  `entity_id` INTEGER NOT NULL,
  `error_code` TEXT NOT NULL,
  `error_message` TEXT NOT NULL,
  `error_help` TEXT,
  `retry_count` INTEGER NOT NULL,
  `created_at` TEXT NOT NULL,
  `notified_at` INTEGER
);

-- ── 词库表组 ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `word` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `spelling_normalized` TEXT NOT NULL,
  `spelling_display` TEXT NOT NULL,
  `phonetic_ipa` TEXT
);

CREATE TABLE IF NOT EXISTS `word_sense` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `word_id` INTEGER NOT NULL,
  `order_index` INTEGER NOT NULL,
  `part_of_speech` TEXT NOT NULL,
  `chinese_meaning` TEXT NOT NULL,
  `english_definition` TEXT NOT NULL,
  FOREIGN KEY(`word_id`) REFERENCES `word`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `example_sentence` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `word_sense_id` INTEGER NOT NULL,
  `order_index` INTEGER NOT NULL,
  `sentence_en` TEXT NOT NULL,
  `sentence_zh` TEXT NOT NULL,
  `is_primary` INTEGER NOT NULL,
  FOREIGN KEY(`word_sense_id`) REFERENCES `word_sense`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `vocabulary_entry` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `word_id` INTEGER NOT NULL,
  `instance_number` INTEGER NOT NULL,
  `status` TEXT NOT NULL,
  `correct_review_streak` INTEGER NOT NULL,
  `mastered_at` TEXT,
  `deleted_at` TEXT,
  `deleted_reason` TEXT,
  FOREIGN KEY(`word_id`) REFERENCES `word`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS `daily_learning` (
  `learning_date` TEXT NOT NULL,
  `ref_batch_date` TEXT NOT NULL,
  `ref_batch_id` INTEGER NOT NULL,
  `daily_count_snapshot` INTEGER NOT NULL,
  PRIMARY KEY(`learning_date`),
  FOREIGN KEY(`ref_batch_id`) REFERENCES `article_batch`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE
);

-- ── TTS 缓存 ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `tts_cache` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `article_paragraph_id` INTEGER REFERENCES `article_paragraph` (`id`) ON DELETE CASCADE,
  `word_id` INTEGER,
  `speed` REAL NOT NULL,
  `voice_id` TEXT NOT NULL,
  `file_path` TEXT NOT NULL,
  `file_size` INTEGER NOT NULL,
  `created_at` INTEGER NOT NULL,
  `last_accessed_at` INTEGER NOT NULL
);

-- ── 索引（名字与 Room 自动命名逐条一致）───────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS `index_article_batch_difficulty_level_snapshot_generated_on` ON `article_batch` (`difficulty_level_snapshot`, `generated_on`);
CREATE INDEX IF NOT EXISTS `index_article_batch_generated_on` ON `article_batch` (`generated_on`);
CREATE INDEX IF NOT EXISTS `index_article_batch_id` ON `article` (`batch_id`);
CREATE INDEX IF NOT EXISTS `index_article_paragraph_article_id` ON `article_paragraph` (`article_id`);
CREATE UNIQUE INDEX IF NOT EXISTS `index_article_paragraph_article_id_order_index` ON `article_paragraph` (`article_id`, `order_index`);
CREATE INDEX IF NOT EXISTS `index_daily_learning_ref_batch_id` ON `daily_learning` (`ref_batch_id`);
CREATE INDEX IF NOT EXISTS `index_example_sentence_word_sense_id` ON `example_sentence` (`word_sense_id`);
CREATE INDEX IF NOT EXISTS `index_generation_error_log_created_at` ON `generation_error_log` (`created_at`);
CREATE INDEX IF NOT EXISTS `index_generation_error_log_entity_type_entity_id` ON `generation_error_log` (`entity_type`, `entity_id`);
CREATE INDEX IF NOT EXISTS `index_vocabulary_entry_word_id` ON `vocabulary_entry` (`word_id`);
CREATE INDEX IF NOT EXISTS `index_word_sense_word_id` ON `word_sense` (`word_id`);
CREATE UNIQUE INDEX IF NOT EXISTS `index_word_spelling_normalized` ON `word` (`spelling_normalized`);
CREATE INDEX IF NOT EXISTS `tts_cache_last_accessed_at_index` ON `tts_cache` (`last_accessed_at`);

-- ── 收尾：版本指针 → 1 + 迁移历史记录 ─────────────────────────────
INSERT OR IGNORE INTO db_version (id, version, updated_at)
  VALUES (1, 1, CAST(strftime('%s','now') AS INTEGER) * 1000);

INSERT INTO schema_migration_log (from_version, to_version, description, created_at)
  VALUES (0, 1, 'migrations/001-init.sql', strftime('%Y-%m-%dT%H:%M:%fZ','now'));

UPDATE db_version SET version = 1, updated_at = CAST(strftime('%s','now') AS INTEGER) * 1000 WHERE id = 1;

COMMIT;
