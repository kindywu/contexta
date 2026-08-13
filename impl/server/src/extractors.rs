use crate::AppState;
use crate::jwt;
use crate::response::AppError;
use crate::services::auth_service;
use axum::extract::FromRequestParts;
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
            .ok_or(AppError::Unauthorized("TOKEN_EXPIRED".into()))?;
        let claims: jwt::AppClaims = jwt::verify_token(&state.cfg, header)
            .map_err(|_| AppError::Unauthorized("TOKEN_EXPIRED".into()))?;
        // M4（审查）：先封禁后会话——被封禁账号应得 403 BANNED，而非 401 EVICTED
        if auth_service::is_banned(&state.pool, &claims.sub).await? {
            return Err(AppError::Banned("account banned".into()));
        }
        // I2（审查）：会话行 issued_at（毫秒）必须与 token 的 iat 完全一致。
        // 行不存在（登出/被挤掉）或 iat 落后（重登刷新了 issued_at）→ 一律 EVICTED
        match auth_service::session_issued_at(&state.pool, &claims.sub, &claims.device_id).await? {
            Some(issued_at) if issued_at == claims.iat => {}
            _ => return Err(AppError::Unauthorized("EVICTED".into())),
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
            .ok_or(AppError::Unauthorized("TOKEN_EXPIRED".into()))?;
        let claims: jwt::AdminClaims = jwt::verify_token(&state.cfg, header)
            .map_err(|_| AppError::Unauthorized("TOKEN_EXPIRED".into()))?;
        if claims.role != "admin" {
            return Err(AppError::Unauthorized("TOKEN_EXPIRED".into()));
        }
        Ok(AdminAuth {
            username: claims.sub,
        })
    }
}
