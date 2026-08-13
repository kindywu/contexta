-- Contexta Server v1 结构（开发期活版本：结构变更并入本文件，不递增版本）
-- 服务端未发布（tool/db_version = 0），本文件是 0→1 起点，全部 IF NOT EXISTS。

CREATE TABLE IF NOT EXISTS schema_migration_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_version INTEGER NOT NULL,
    to_version INTEGER NOT NULL,
    description TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    phone TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'normal',              -- normal | banned
    banned_reason TEXT,
    quota_word_daily INTEGER,                           -- null = 全局默认
    quota_article_daily INTEGER,                        -- null = 全局默认（预留，当前文章为全局池）
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS admin_user (
    username TEXT PRIMARY KEY,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS device_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL REFERENCES users(phone),
    device_id TEXT NOT NULL,
    issued_at INTEGER NOT NULL,
    last_active_at INTEGER NOT NULL,
    UNIQUE(phone, device_id)
);
CREATE INDEX IF NOT EXISTS idx_device_sessions_phone ON device_sessions(phone);

CREATE TABLE IF NOT EXISTS article (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_date TEXT NOT NULL,                          -- ISO YYYY-MM-DD
    difficulty TEXT NOT NULL,                           -- LOW | MEDIUM | HIGH
    content_category TEXT NOT NULL,
    order_index INTEGER NOT NULL,
    title TEXT,
    status TEXT NOT NULL DEFAULT 'pending_review',      -- pending_review | approved | rejected | rejected_final
    reject_reason TEXT,
    regenerate_count INTEGER NOT NULL DEFAULT 0,
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_article_date_diff_status ON article(target_date, difficulty, status);
CREATE INDEX IF NOT EXISTS idx_article_status ON article(status);

CREATE TABLE IF NOT EXISTS article_paragraph (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER NOT NULL REFERENCES article(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    text TEXT NOT NULL,
    UNIQUE(article_id, order_index)
);

CREATE TABLE IF NOT EXISTS usage_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT,                                         -- null = 服务端任务侧
    endpoint TEXT NOT NULL,                             -- word_lookup | article_generate
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    latency_ms INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_usage_phone_created ON usage_log(phone, created_at);
CREATE INDEX IF NOT EXISTS idx_usage_created ON usage_log(created_at);

CREATE TABLE IF NOT EXISTS word_lookup_cache (
    word TEXT PRIMARY KEY,
    result_json TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
