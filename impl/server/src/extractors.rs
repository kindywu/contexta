use crate::AppState;
use crate::jwt;
use crate::response::AppError;
use crate::services::auth_service;
use axum::extract::{FromRequestParts, State};
use axum::http::StatusCode;
use axum::http::request::Parts;

pub struct AuthUser {
    pub phone: String,
    pub device_id: String,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;
    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or(AppError::Unauthorized("TOKEN_EXPIRED"))?;
        let claims: jwt::AppClaims = jwt::verify_token(&state.cfg, header)
            .map_err(|_| AppError::Unauthorized("TOKEN_EXPIRED"))?;
        if !auth_service::session_alive(&state.pool, &claims.sub, &claims.device_id).await? {
            return Err(AppError::Unauthorized("EVICTED"));
        }
        if auth_service::is_banned(&state.pool, &claims.sub).await? {
            return Err(AppError::Banned("account banned"));
        }
        Ok(AuthUser {
            phone: claims.sub,
            device_id: claims.device_id,
        })
    }
}

pub struct AdminAuth {
    pub username: String,
}

impl FromRequestParts<AppState> for AdminAuth {
    type Rejection = AppError;
    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or(AppError::Unauthorized("TOKEN_EXPIRED"))?;
        let claims: jwt::AdminClaims = jwt::verify_token(&state.cfg, header)
            .map_err(|_| AppError::Unauthorized("TOKEN_EXPIRED"))?;
        if claims.role != "admin" {
            return Err(AppError::Unauthorized("TOKEN_EXPIRED"));
        }
        Ok(AdminAuth {
            username: claims.sub,
        })
    }
}

// 显式声明 rejection 状态码（axum 要求 IntoResponse）
impl From<AppError> for StatusCode {
    fn from(_: AppError) -> Self {
        StatusCode::UNAUTHORIZED
    }
}
