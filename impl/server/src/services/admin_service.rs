use crate::config::Config;
use crate::jwt;
use crate::response::AppError;
use argon2::password_hash::PasswordVerifier;
use argon2::{Argon2, PasswordHash};
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
    let (hash,) = row.ok_or(AppError::Unauthorized("TOKEN_EXPIRED"))?;
    let parsed = PasswordHash::new(&hash).map_err(|_| AppError::Unauthorized("TOKEN_EXPIRED"))?;
    if Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_err()
    {
        return Err(AppError::Unauthorized("TOKEN_EXPIRED"));
    }
    Ok(jwt::issue_admin_token(cfg, username)?)
}
