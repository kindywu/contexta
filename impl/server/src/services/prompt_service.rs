//! prompt 服务——LLM prompt 的唯一来源是 DB（prompt 表），管理端可编辑。
//!
//! - `get_prompt`：DB 行读取；缺行（种子缺失/行被删）→ PipelineBlocking 500
//!   （数据完整性问题；运行期调用方只用 PROMPT_KEYS 白名单 key）。
//! - `update_prompt`：白名单 key（PROMPT_KEYS）+ 非空校验，UPSERT（updated_at 刷新）。
//! - 种子：001-init.sql `INSERT OR IGNORE` 7 行（updated_at=0 标记种子，重复 migrate 幂等，
//!   不覆盖管理端已改内容）。

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

/// 取 prompt 内容：DB 行读取；缺行 → 500（种子缺失/行被删，数据完整性问题）。
pub async fn get_prompt(pool: &SqlitePool, key: &str) -> Result<String, AppError> {
    let row: Option<String> = sqlx::query_scalar("SELECT content FROM prompt WHERE key = ?")
        .bind(key)
        .fetch_optional(pool)
        .await?;
    row.ok_or_else(|| {
        AppError::PipelineBlocking(format!("prompt key '{key}' missing in DB"))
    })
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
