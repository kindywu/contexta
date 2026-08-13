use crate::config::Config;
use crate::jwt;
use crate::response::AppError;
use chrono::Utc;
use sqlx::SqlitePool;

const MAX_ACTIVE_DEVICES: i64 = 2;

pub async fn login(
    pool: &SqlitePool,
    cfg: &Config,
    phone: &str,
    device_id: &str,
) -> Result<String, AppError> {
    let now = Utc::now().timestamp_millis();
    // 自动注册
    sqlx::query(
        "INSERT INTO users (phone, status, created_at, updated_at) VALUES (?, 'normal', ?, ?)
         ON CONFLICT(phone) DO NOTHING",
    )
    .bind(phone)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?;
    if is_banned(pool, phone).await? {
        return Err(AppError::Banned("account banned"));
    }
    // I1（审查）：同一设备重登 → 替换自身会话并刷新 issued_at（挤掉次序按最近活跃重排）。
    // max(旧 issued_at + 1, now) 保证 issued_at 严格单调递增：同毫秒重登也不会产生相同值，
    // 与 I2 的 `iat == issued_at` 精确校验配合，旧 token 必然失效。
    sqlx::query(
        "INSERT INTO device_sessions (phone, device_id, issued_at, last_active_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(phone, device_id) DO UPDATE SET
             last_active_at = excluded.last_active_at,
             issued_at = max(device_sessions.issued_at + 1, excluded.issued_at)",
    )
    .bind(phone)
    .bind(device_id)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?;
    // 挤掉：保留按 issued_at 最新的 2 条（含刚插入的）；
    // 适配（T3 记录）：同毫秒 issued_at 平局时按 id DESC 兜底，保证淘汰确定性（id 单调递增）
    sqlx::query(
        "DELETE FROM device_sessions
         WHERE phone = ? AND id NOT IN (
             SELECT id FROM device_sessions WHERE phone = ?
             ORDER BY issued_at DESC, id DESC LIMIT ?)",
    )
    .bind(phone)
    .bind(phone)
    .bind(MAX_ACTIVE_DEVICES)
    .execute(pool)
    .await?;
    // I2（审查）：token 的 iat 取会话行实际落库的 issued_at（upsert 可能被 +1 单调化），
    // 保证 `claims.iat == issued_at` 精确成立
    let issued_at: i64 = sqlx::query_scalar(
        "SELECT issued_at FROM device_sessions WHERE phone = ? AND device_id = ?",
    )
    .bind(phone)
    .bind(device_id)
    .fetch_one(pool)
    .await?;
    Ok(jwt::issue_app_token(cfg, phone, device_id, issued_at)?)
}

pub async fn logout(pool: &SqlitePool, phone: &str, device_id: &str) -> Result<(), AppError> {
    sqlx::query("DELETE FROM device_sessions WHERE phone = ? AND device_id = ?")
        .bind(phone)
        .bind(device_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// 会话行的 issued_at（毫秒，签发时刻）；None = 无会话（登出/被挤掉）。
/// 替代原 session_alive：AuthUser 提取器需要行值做 `iat == issued_at` 精确校验（I2）。
pub async fn session_issued_at(
    pool: &SqlitePool,
    phone: &str,
    device_id: &str,
) -> Result<Option<i64>, AppError> {
    let issued: Option<i64> = sqlx::query_scalar(
        "SELECT issued_at FROM device_sessions WHERE phone = ? AND device_id = ?",
    )
    .bind(phone)
    .bind(device_id)
    .fetch_optional(pool)
    .await?;
    Ok(issued)
}

pub async fn is_banned(pool: &SqlitePool, phone: &str) -> Result<bool, AppError> {
    let status: Option<String> = sqlx::query_scalar("SELECT status FROM users WHERE phone = ?")
        .bind(phone)
        .fetch_optional(pool)
        .await?;
    Ok(status.as_deref() == Some("banned"))
}
