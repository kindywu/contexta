use crate::config::Config;
use crate::jwt;
use crate::response::AppError;
use crate::services::today_start_millis;
use argon2::password_hash::PasswordVerifier;
use argon2::{Argon2, PasswordHash};
use chrono::Utc;
use sqlx::SqlitePool;

/// 管理员登录：查 admin_user 行 → argon2 校验密码 → 签发 admin JWT（role: admin）。
/// 用户名不存在 / 哈希解析失败 / 密码不匹配一律返回 401 TOKEN_EXPIRED
/// （不区分具体失败原因，避免用户枚举）。
pub async fn login(
    pool: &SqlitePool,
    cfg: &Config,
    username: &str,
    password: &str,
) -> Result<String, AppError> {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT password_hash FROM admin_user WHERE username = ?")
            .bind(username)
            .fetch_optional(pool)
            .await?;
    let (hash,) = row.ok_or(AppError::Unauthorized("TOKEN_EXPIRED".into()))?;
    let parsed =
        PasswordHash::new(&hash).map_err(|_| AppError::Unauthorized("TOKEN_EXPIRED".into()))?;
    if Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_err()
    {
        return Err(AppError::Unauthorized("TOKEN_EXPIRED".into()));
    }
    Ok(jwt::issue_admin_token(cfg, username)?)
}

/// 用户列表：users 全表 + 每人今日查词次数（usage_log word_lookup，created_at >= 今日零点，
/// 复用 services::today_start_millis——与 llm_service::check_quota 同一口径）。
/// 返回 JSON 数组，按 created_at 升序。quota_article_daily 为文章全局池预留列，暂不外露。
pub async fn list_users(pool: &SqlitePool) -> Result<Vec<serde_json::Value>, AppError> {
    let rows: Vec<(String, String, Option<String>, i64, Option<i64>, Option<i64>)> = sqlx::query_as(
        "SELECT phone, status, banned_reason, created_at, quota_word_daily, quota_article_daily FROM users ORDER BY created_at",
    ).fetch_all(pool).await?;
    let mut out = Vec::new();
    for (phone, status, reason, created_at, qw, _qa) in rows {
        let start = today_start_millis();
        let today_usage: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM usage_log WHERE phone = ? AND endpoint = 'word_lookup' AND created_at >= ?",
        ).bind(&phone).bind(start).fetch_one(pool).await?;
        out.push(serde_json::json!({
            "phone": phone, "status": status, "banned_reason": reason,
            "created_at": created_at, "quota_word_daily": qw, "today_word_lookups": today_usage,
        }));
    }
    Ok(out)
}

/// 封禁/解封：status 写 banned/normal，banned_reason 同步（解封置 NULL），updated_at 刷新。
/// 注意：phone 不存在时 UPDATE 0 行静默成功（简报参考实现原样，未加 404 语义）。
pub async fn set_status(
    pool: &SqlitePool,
    phone: &str,
    status: &str,
    reason: Option<&str>,
) -> Result<(), AppError> {
    let now = Utc::now().timestamp_millis();
    sqlx::query("UPDATE users SET status = ?, banned_reason = ?, updated_at = ? WHERE phone = ?")
        .bind(status)
        .bind(reason)
        .bind(now)
        .bind(phone)
        .execute(pool)
        .await?;
    Ok(())
}

/// 配额覆盖：quota_word_daily 置值（NULL = 清覆盖，回落全局默认），updated_at 刷新。
/// llm_service::user_quota 的 fetch_optional 对 NULL 列回退 cfg.word_quota_daily，天然衔接。
pub async fn set_quota(
    pool: &SqlitePool,
    phone: &str,
    word_daily: Option<i64>,
) -> Result<(), AppError> {
    let now = Utc::now().timestamp_millis();
    sqlx::query("UPDATE users SET quota_word_daily = ?, updated_at = ? WHERE phone = ?")
        .bind(word_daily)
        .bind(now)
        .bind(phone)
        .execute(pool)
        .await?;
    Ok(())
}

/// 今日用量汇总：按 (phone, endpoint) 聚合调用次数与 token 总量，created_at >= 今日零点。
/// phone 为 NULL 的行 = 服务端任务侧（文章生成等），单独成组保留。
pub async fn usage_report(pool: &SqlitePool) -> Result<Vec<serde_json::Value>, AppError> {
    let rows: Vec<(Option<String>, String, i64, i64, i64)> = sqlx::query_as(
        "SELECT phone, endpoint, COUNT(*), SUM(prompt_tokens), SUM(completion_tokens)
         FROM usage_log WHERE created_at >= ? GROUP BY phone, endpoint ORDER BY phone, endpoint",
    )
    .bind(today_start_millis())
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .map(
            |(phone, endpoint, calls, prompt_tokens, completion_tokens)| {
                serde_json::json!({
                    "phone": phone,
                    "endpoint": endpoint,
                    "calls": calls,
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                })
            },
        )
        .collect())
}
