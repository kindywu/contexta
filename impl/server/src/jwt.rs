use crate::config::Config;
use chrono::Utc;
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct AppClaims {
    pub sub: String, // phone
    pub device_id: String,
    pub exp: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AdminClaims {
    pub sub: String, // username
    pub role: String,
    pub exp: i64,
}

const APP_TOKEN_TTL_SECS: i64 = 30 * 24 * 3600;

pub fn issue_app_token(cfg: &Config, phone: &str, device_id: &str) -> anyhow::Result<String> {
    let claims = AppClaims {
        sub: phone.to_string(),
        device_id: device_id.to_string(),
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
        exp: Utc::now().timestamp() + APP_TOKEN_TTL_SECS,
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
