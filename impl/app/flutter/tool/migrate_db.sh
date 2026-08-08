#!/usr/bin/env bash
#
# 数据库升级脚本：为旧 schema 的 contexta.db 补上 tts_cache 表（v1 → 当前）。
#
# 背景：开发期 schema 变更不递增版本、不写 drift Migration（见 CLAUDE.md
# MIGRATION 约定），覆盖安装不会重建表。本地备份库 / 真机旧库需要手工补表。
#
# 用法：
#   ./tool/migrate_db.sh <contexta.db 路径>
#   （默认对备份库执行；--check 只打印差异，不修改）
set -euo pipefail

DB="${1:?用法: migrate_db.sh <db路径> [--check]}"
CHECK="${2:-}"

if [ ! -f "$DB" ]; then
  echo "❌ 数据库不存在: $DB"
  exit 1
fi

# 幂等：已有 tts_cache 表则跳过
if sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='tts_cache';" | grep -q tts_cache; then
  echo "✅ tts_cache 已存在，无需升级: $DB"
  exit 0
fi

echo "🔧 升级数据库: $DB"

apply() {
  sqlite3 "$DB" <<'SQL'
-- tts_cache 表（对照 lib/data/local/tables/tts_cache_tables.dart）
CREATE TABLE `tts_cache` (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  `article_paragraph_id` INTEGER REFERENCES `article_paragraph` (`id`) ON DELETE CASCADE,
  `word_id` INTEGER,
  `speed` REAL NOT NULL,
  `file_path` TEXT NOT NULL,
  `file_size` INTEGER NOT NULL,
  `created_at` INTEGER NOT NULL,
  `last_accessed_at` INTEGER NOT NULL
);
CREATE INDEX `tts_cache_last_accessed_at_index` ON `tts_cache` (`last_accessed_at`);
SQL
}

if [ "$CHECK" = "--check" ]; then
  echo "（--check 模式，仅展示将执行的 SQL）"
  apply || true
else
  apply
  echo "✅ 升级完成: $DB"
  sqlite3 "$DB" ".tables" | tr ' ' '\n' | grep -c tts_cache | xargs -I{} echo "tts_cache 表数: {}"
fi
