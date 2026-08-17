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
    status TEXT NOT NULL DEFAULT 'pending_review',      -- pending_review | approved | rejected | rejected_final | failed（failed=生成失败，title 为 NULL，不计入非终结）
    reject_reason TEXT,
    regenerate_count INTEGER NOT NULL DEFAULT 0,
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    source_article_id INTEGER,                          -- 事实源（chinadaily）引用，仅 NEWS 有值
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

-- NEWS 分类事实锚定：chinadaily 抓取入库的事实源（URL 唯一键，is_used 预占标记）。
CREATE TABLE IF NOT EXISTS article_source (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    source_url   TEXT    NOT NULL UNIQUE,      -- 事实源唯一键（去重依据）
    title        TEXT    NOT NULL,
    body         TEXT    NOT NULL,             -- 正文纯文本（生成时注入 prompt；存库免重抓）
    published_at TEXT    NOT NULL,             -- YYYY-MM-DD（URL 路径日期）
    is_used      INTEGER NOT NULL DEFAULT 0,   -- 已引用标记（并发选中原子性）
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL,
    is_deleted   INTEGER NOT NULL DEFAULT 0,
    deleted_at   INTEGER
);
CREATE INDEX IF NOT EXISTS idx_article_source_used_date
    ON article_source(is_used, published_at);

-- Task 2：LLM prompt 存储化（管理端可编辑）。prompt 表是 prompt 的唯一来源，
-- 种子即默认内容（updated_at=0 标记种子）。INSERT OR IGNORE：重复 migrate
-- 不覆盖管理端已改内容。内容含 ';'（字符串字面量内），
-- 依赖 db.rs split_statements 的引号感知切分。
CREATE TABLE IF NOT EXISTS prompt (
    key TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

INSERT OR IGNORE INTO prompt (key, content, updated_at) VALUES
    ('word_lookup_system', 'You are an English-Chinese dictionary assistant.
Given an English word, provide its detailed definition for Chinese learners.

Output format:
<spelling>TheWord</spelling>
<phonetic>/fəˈnɛtɪk/</phonetic>
<sense>
  <partOfSpeech>n.</partOfSpeech>
  <chineseMeaning>中文释义</chineseMeaning>
  <englishDefinition>English definition of this sense.</englishDefinition>
  <example>
    <en>Example sentence in English.</en>
    <zh>例句的中文翻译。</zh>
  </example>
</sense>

Rules:
- <phonetic> is optional — include if available, omit the tag entirely if unknown
- Provide 1-3 <sense> blocks; at least 1 is required
- Each <sense> must have <partOfSpeech>, <chineseMeaning>, <englishDefinition>
- Each <sense> should have 0-2 <example> blocks; <example> is optional
- <example> must contain both <en> and <zh>
- Output only the XML — no explanations, no markdown
- Escape XML special characters: & → &amp;, < → &lt;, > → &gt;
- The root element must be <spelling> — never wrap the word in a custom tag (e.g. <ocean>ocean</ocean>)
', 0),
    ('word_lookup_user', 'Look up the word: {{word}}

Provide the spelling, phonetic transcription (if known), and all common senses with example sentences.', 0),
    ('article_common', 'You are an English language learning content creator.
You create articles for Chinese learners at various difficulty levels.

Output format:
<title>{{title}}</title>
<paragraph>English sentence here.</paragraph>
<translation>中文翻译。</translation>
<paragraph>Next sentence.</paragraph>
<translation>下一句翻译。</translation>

Rules:
- Each paragraph must be 1-3 sentences, not longer
- Each <paragraph> must be immediately followed by <translation>
- Title must be 2-8 words
- Output only the XML — no explanations, no markdown', 0),
    ('article_low', 'Article length: total English word count must be 50-100 words.', 0),
    ('article_medium', 'Article length: total English word count must be 100-300 words.', 0),
    ('article_high', 'Article length: total English word count must be 300-600 words.', 0),
    ('article_user_prompt', 'Create article #{{orderIndex}} in the category: {{category}}

{{sourceArticle}}

{{recentTitles}}', 0);
