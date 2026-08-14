use crate::config::Config;
use crate::drivers::deepseek::{DeepSeekApi, call_with_retry};
use crate::llm::parser::{WordLookup, parse_word_lookup};
use crate::prompts::{build_article_system, build_article_user, build_word_lookup_system, build_word_lookup_user};
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

/// executor 泛型：&SqlitePool 与 &mut SqliteConnection 均可执行——
/// 文章生成（T8）在 BEGIN IMMEDIATE 事务内记账时须用事务连接，事务外/查词用 pool。
pub async fn record_usage<'e, E>(
    exec: E,
    phone: Option<&str>,
    endpoint: &str,
    prompt_tokens: u64,
    completion_tokens: u64,
    latency_ms: i64,
) -> Result<(), AppError>
where
    E: sqlx::Executor<'e, Database = sqlx::Sqlite>,
{
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
    .execute(exec)
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
    // 缓存（命中但反序列化失败 = 坏缓存：删行自愈，继续走 LLM）
    let cached: Option<String> = sqlx::query_scalar(
        "SELECT result_json FROM word_lookup_cache WHERE word = ? AND created_at >= ?",
    )
    .bind(&key)
    .bind(Utc::now().timestamp_millis() - cfg.cache_ttl_days * 86_400_000)
    .fetch_optional(pool)
    .await?;
    if let Some(json) = cached {
        match serde_json::from_str(&json) {
            Ok(v) => return Ok(v),
            Err(_) => {
                tracing::warn!(
                    "corrupt word_lookup_cache row for {key:?}, deleting and re-generating"
                );
                if let Err(e) = sqlx::query("DELETE FROM word_lookup_cache WHERE word = ?")
                    .bind(&key)
                    .execute(pool)
                    .await
                {
                    tracing::warn!("failed to delete corrupt cache row {key:?}: {e:?}");
                }
            }
        }
    }
    // 配额
    check_quota(pool, cfg, phone).await?;
    // LLM（Task 2：prompt DB 化——system/user 均从 prompt 表读取，缺行回退嵌入默认）
    let system = build_word_lookup_system(pool).await?;
    let user = build_word_lookup_user(pool, word).await?;
    let started = tokio::time::Instant::now();
    let resp = call_with_retry(api, &system, &user, cfg.llm_timeout_secs).await?;
    let latency = started.elapsed().as_millis() as i64;
    // 用量记账：LLM 调用成功（真实花钱）即记账，无论解析/写缓存结果如何——
    // 解析失败也计配额，堵住"易触发解析失败的词无限烧钱"的绕过口。
    // 记账失败仅降级告警（磁盘满/写繁忙时不得把成功查词变 500）。
    if let Err(e) = record_usage(
        pool,
        Some(phone),
        "word_lookup",
        resp.prompt_tokens,
        resp.completion_tokens,
        latency,
    )
    .await
    {
        tracing::warn!("record_usage failed for word_lookup {key:?}: {e:?}");
    }
    let parsed = parse_word_lookup(&resp.content)
        .ok_or_else(|| AppError::PipelineBlocking("unparseable LLM response".into()))?;
    // 写缓存：spelling 与请求词不一致（LLM 输出变体/屈折）不入缓存，
    // 否则请求词 key 会向全用户共享缓存写入错误词条；写失败仅降级告警（结果仍返回）。
    if parsed.spelling.to_lowercase() == key
        && let Err(e) = write_cache(pool, cfg, &key, &parsed).await
    {
        tracing::warn!("word_lookup cache write failed for {key:?}: {e:?}");
    }
    Ok(parsed)
}

/// 写缓存（容量上限：超则删最旧一条）。
async fn write_cache(
    pool: &SqlitePool,
    cfg: &Config,
    key: &str,
    parsed: &WordLookup,
) -> Result<(), AppError> {
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
    .bind(key)
    .bind(serde_json::to_string(parsed)?)
    .bind(Utc::now().timestamp_millis())
    .execute(pool)
    .await?;
    Ok(())
}

// 供文章任务（T8）复用；回传 token 数（审查要求：成本换算）
// Task 2：prompt DB 化——新增 pool 参数（system/user 从 prompt 表读取，缺行回退嵌入默认；
// 未知 key → BadRequest 直接上抛，difficulty 由 DIFFICULTIES 白名单保证不会触发）。
pub async fn generate_article_content(
    pool: &SqlitePool,
    api: &dyn DeepSeekApi,
    cfg: &Config,
    difficulty: &str,
    category: &str,
    order_index: i64,
) -> Result<(String, Vec<(i64, String, String)>, u64, u64), AppError> {
    let system = build_article_system(pool, difficulty).await?;
    let user = build_article_user(pool, category, order_index).await?;
    let resp = call_with_retry(api, &system, &user, cfg.llm_timeout_secs).await?;
    let draft = crate::llm::parser::parse_article(&resp.content);
    Ok((
        draft.title,
        draft.paragraphs,
        resp.prompt_tokens,
        resp.completion_tokens,
    ))
}
