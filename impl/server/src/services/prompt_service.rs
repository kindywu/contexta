//! Task 2：prompt 存储化服务——LLM prompt 从编译期嵌入改为数据库存储（管理端可编辑）。
//!
//! - `get_prompt`：DB 行优先；缺行回退嵌入默认（`embedded_default`，来自
//!   `src/prompts/*.txt` 编译期嵌入）；未知 key → BadRequest。
//! - `update_prompt`：白名单 key（PROMPT_KEYS）+ 非空校验，UPSERT（updated_at 刷新）。
//! - 种子：001-init.sql `INSERT OR IGNORE` 7 行（updated_at=0 标记种子，重复 migrate 幂等，
//!   不覆盖管理端已改内容）。

use crate::prompts::{ARTICLE_SYSTEM, WORD_LOOKUP_SYSTEM, load_section};
use crate::response::AppError;
use chrono::Utc;
use serde::Serialize;
use sqlx::SqlitePool;

/// 全部可管理 prompt key（白名单，与 001 种子一一对应；拼写精确，不得改）。
pub const PROMPT_KEYS: [&str; 7] = [
    "word_lookup_system",
    "word_lookup_user",
    "article_common",
    "article_low",
    "article_medium",
    "article_high",
    "article_user_prompt",
];

/// word_lookup_user 的嵌入默认（与 llm_service 原内联字符串逐字一致）。
const WORD_LOOKUP_USER_DEFAULT: &str = "Look up the word: {{word}}\n\nProvide the spelling, phonetic transcription (if known), and all common senses with example sentences.";

/// 嵌入默认：编译期 txt 按 key 分节拆出（DB 缺行时的回退，保证运行时语义不因缺行变化）。
/// 与 001 种子内容同源（种子生成脚本按同一分节语义产出），测试断言两者逐字相等。
pub fn embedded_default(key: &str) -> Option<String> {
    match key {
        "word_lookup_system" => Some(WORD_LOOKUP_SYSTEM.to_string()),
        "word_lookup_user" => Some(WORD_LOOKUP_USER_DEFAULT.to_string()),
        "article_common" => load_section(ARTICLE_SYSTEM, &["COMMON"], &[]),
        "article_low" => load_section(ARTICLE_SYSTEM, &["LOW"], &[]),
        "article_medium" => load_section(ARTICLE_SYSTEM, &["MEDIUM"], &[]),
        "article_high" => load_section(ARTICLE_SYSTEM, &["HIGH"], &[]),
        "article_user_prompt" => load_section(ARTICLE_SYSTEM, &["USER_PROMPT"], &[]),
        _ => None,
    }
}

/// 取 prompt 内容：DB 行优先，缺行回退嵌入默认；两路皆无（未知 key）→ 400。
pub async fn get_prompt(pool: &SqlitePool, key: &str) -> Result<String, AppError> {
    let row: Option<String> = sqlx::query_scalar("SELECT content FROM prompt WHERE key = ?")
        .bind(key)
        .fetch_optional(pool)
        .await?;
    match row {
        Some(c) => Ok(c),
        None => embedded_default(key).ok_or_else(|| {
            AppError::BadRequest("BAD_PARAM".into(), "unknown prompt key".into())
        }),
    }
}

#[derive(Serialize)]
pub struct PromptView {
    pub key: String,
    pub content: String,
    pub updated_at: i64,
}

/// 全量列表（管理端 GET）：按 key 排序。
pub async fn get_all_prompts(pool: &SqlitePool) -> Result<Vec<PromptView>, AppError> {
    let rows: Vec<(String, String, i64)> =
        sqlx::query_as("SELECT key, content, updated_at FROM prompt ORDER BY key")
            .fetch_all(pool)
            .await?;
    Ok(rows
        .into_iter()
        .map(|(key, content, updated_at)| PromptView {
            key,
            content,
            updated_at,
        })
        .collect())
}

/// 更新 prompt（管理端 PUT）：白名单 key + 非空校验（400），UPSERT 刷新 updated_at。
/// 未知 key 或空内容零写入。
pub async fn update_prompt(pool: &SqlitePool, key: &str, content: &str) -> Result<(), AppError> {
    if !PROMPT_KEYS.contains(&key) {
        return Err(AppError::BadRequest(
            "BAD_PARAM".into(),
            "unknown prompt key".into(),
        ));
    }
    if content.trim().is_empty() {
        return Err(AppError::BadRequest(
            "BAD_PARAM".into(),
            "content required".into(),
        ));
    }
    sqlx::query(
        "INSERT INTO prompt (key, content, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at",
    )
    .bind(key)
    .bind(content.trim())
    .bind(Utc::now().timestamp_millis())
    .execute(pool)
    .await?;
    Ok(())
}
