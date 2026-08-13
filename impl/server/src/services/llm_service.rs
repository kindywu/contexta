use crate::config::Config;
use crate::drivers::deepseek::{DeepSeekApi, call_with_retry};
use crate::llm::parser::{WordLookup, parse_word_lookup};
use crate::prompts::{build_article_system, build_article_user, build_word_lookup_system};
use crate::response::AppError;
use crate::services::today_start_millis;
use chrono::Utc;
use sqlx::SqlitePool;

pub async fn check_quota(pool: &SqlitePool, cfg: &Config, phone: &str) -> Result<(), AppError> {
    let quota = user_quota(pool, cfg, phone).await?;
    let start = today_start_millis();
    let used: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM usage_log WHERE phone = ? AND endpoint = 'word_lookup' AND created_at >= ?",
    ).bind(phone).bind(start).fetch_one(pool).await?;
    if used >= quota {
        return Err(AppError::QuotaExceeded(
            "daily word lookup quota exceeded".into(),
        ));
    }
    Ok(())
}

async fn user_quota(pool: &SqlitePool, cfg: &Config, phone: &str) -> Result<i64, AppError> {
    // users.quota_word_daily 可空：fetch_optional 对 Option<i64> 列返回 Option<Option<i64>>，
    // flatten 解一层后 unwrap_or 回退全局默认配额。
    let override_q: Option<Option<i64>> =
        sqlx::query_scalar("SELECT quota_word_daily FROM users WHERE phone = ?")
            .bind(phone)
            .fetch_optional(pool)
            .await?;
    Ok(override_q.flatten().unwrap_or(cfg.word_quota_daily))
}

pub async fn record_usage(
    pool: &SqlitePool,
    phone: Option<&str>,
    endpoint: &str,
    prompt_tokens: u64,
    completion_tokens: u64,
    latency_ms: i64,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at)
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(phone)
    .bind(endpoint)
    .bind(prompt_tokens as i64)
    .bind(completion_tokens as i64)
    .bind(latency_ms)
    .bind(Utc::now().timestamp_millis())
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn word_lookup(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    phone: &str,
    word: &str,
) -> Result<WordLookup, AppError> {
    let key = word.trim().to_lowercase();
    if key.is_empty() {
        return Err(AppError::BadRequest(
            "BAD_PARAM".into(),
            "empty word".into(),
        ));
    }
    // 缓存
    let cached: Option<String> = sqlx::query_scalar(
        "SELECT result_json FROM word_lookup_cache WHERE word = ? AND created_at >= ?",
    )
    .bind(&key)
    .bind(Utc::now().timestamp_millis() - cfg.cache_ttl_days * 86_400_000)
    .fetch_optional(pool)
    .await?;
    if let Some(json) = cached {
        return serde_json::from_str(&json)
            .map_err(|_| AppError::PipelineBlocking("corrupt cache".into()));
    }
    // 配额
    check_quota(pool, cfg, phone).await?;
    // LLM
    let started = tokio::time::Instant::now();
    let resp = call_with_retry(
        api,
        build_word_lookup_system(),
        &format!("Look up the word: {word}\n\nProvide the spelling, phonetic transcription (if known), and all common senses with example sentences."),
        cfg.llm_timeout_secs,
    )
    .await?;
    let latency = started.elapsed().as_millis() as i64;
    let parsed = parse_word_lookup(&resp.content)
        .ok_or_else(|| AppError::PipelineBlocking("unparseable LLM response".into()))?;
    // 写缓存（容量上限：超则删最旧一条）
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM word_lookup_cache")
        .fetch_one(pool)
        .await?;
    if count >= cfg.cache_max_rows {
        sqlx::query("DELETE FROM word_lookup_cache WHERE word = (SELECT word FROM word_lookup_cache ORDER BY created_at ASC LIMIT 1)")
            .execute(pool)
            .await?;
    }
    sqlx::query(
        "INSERT OR REPLACE INTO word_lookup_cache (word, result_json, created_at) VALUES (?, ?, ?)",
    )
    .bind(&key)
    .bind(serde_json::to_string(&parsed)?)
    .bind(Utc::now().timestamp_millis())
    .execute(pool)
    .await?;
    record_usage(
        pool,
        Some(phone),
        "word_lookup",
        resp.prompt_tokens,
        resp.completion_tokens,
        latency,
    )
    .await?;
    Ok(parsed)
}

// 供文章任务（T8）复用
pub async fn generate_article_content(
    api: &dyn DeepSeekApi,
    cfg: &Config,
    difficulty: &str,
    category: &str,
    order_index: i64,
) -> Result<(String, Vec<(i64, String, String)>), AppError> {
    let system = build_article_system(difficulty)
        .ok_or_else(|| AppError::PipelineBlocking("missing article prompt".into()))?;
    let user = build_article_user(category, order_index)
        .ok_or_else(|| AppError::PipelineBlocking("missing article user prompt".into()))?;
    let resp = call_with_retry(api, &system, &user, cfg.llm_timeout_secs).await?;
    let draft = crate::llm::parser::parse_article(&resp.content);
    Ok((draft.title, draft.paragraphs))
}
