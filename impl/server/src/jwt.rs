use crate::config::Config;
use chrono::Utc;
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct AppClaims {
    pub sub: String, // phone
    pub device_id: String,
    // I2（审查）：签发时刻（毫秒），与会话行 device_sessions.issued_at 精确一致。
    // 说明：JWT 惯例 iat 用秒，但重登校验要求 `claims.iat == issued_at` 精确相等——
    // 秒粒度无法区分同秒内的两次重登（测试与真实快速重登都会踩中），故用毫秒对齐。
    pub iat: i64,
    pub exp: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AdminClaims {
    pub sub: String, // username
    pub role: String,
    pub exp: i64,
}

pub const APP_TOKEN_TTL_SECS: i64 = 30 * 24 * 3600;
// T4（审查遗留）：admin token 用更短 TTL（12 小时）——admin 会话被窃取时缩小暴露窗口；
// App token 仍 30 天。登录接口的 expires_at 字段（App 侧）不受影响。
pub const ADMIN_TOKEN_TTL_SECS: i64 = 12 * 3600;

/// iat 由调用方传入（login 内会话行 issued_at 的回读值，同一毫秒读数）：
/// 保证 `claims.iat == issued_at` 精确成立；重登刷新 issued_at 即令旧 token 失效。
pub fn issue_app_token(
    cfg: &Config,
    phone: &str,
    device_id: &str,
    issued_at_ms: i64,
) -> anyhow::Result<String> {
    let claims = AppClaims {
        sub: phone.to_string(),
        device_id: device_id.to_string(),
        iat: issued_at_ms,
        exp: Utc::now().timestamp() + APP_TOKEN_TTL_SECS,
    };
    Ok(encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(cfg.jwt_secret.as_bytes()),
    )?)
}

pub fn issue_admin_token(cfg: &Config, username: &str) -> anyhow::Result<String> {
    let claims = AdminClaims {
        sub: username.to_string(),
        role: "admin".to_string(),
        exp: Utc::now().timestamp() + ADMIN_TOKEN_TTL_SECS,
    };
    Ok(encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(cfg.jwt_secret.as_bytes()),
    )?)
}

pub fn verify_token<T: for<'de> Deserialize<'de>>(cfg: &Config, token: &str) -> anyhow::Result<T> {
    let data = decode::<T>(
        token,
        &DecodingKey::from_secret(cfg.jwt_secret.as_bytes()),
        &Validation::default(),
    )?;
    Ok(data.claims)
}
