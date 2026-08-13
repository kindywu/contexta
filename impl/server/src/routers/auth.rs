use crate::AppState;
use crate::extractors::AuthUser;
use crate::response::{ApiResult, AppError, ok};
use crate::services::auth_service;
use axum::Json;
use axum::extract::State;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
pub struct LoginRequest {
    pub phone: String,
    pub device_id: String,
    pub code: Option<String>,
}

#[derive(Serialize)]
pub struct LoginData {
    pub token: String,
    pub expires_at: i64,
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<ApiResult<LoginData>>, AppError> {
    if req.phone.is_empty() || req.device_id.is_empty() {
        return Err(AppError::BadRequest(
            "BAD_PARAM",
            "phone and device_id required",
        ));
    }
    let token = auth_service::login(&state.pool, &state.cfg, &req.phone, &req.device_id).await?;
    let expires_at = chrono::Utc::now().timestamp() + 30 * 24 * 3600;
    Ok(ok(LoginData { token, expires_at }))
}

#[derive(Deserialize)]
pub struct LogoutRequest {
    pub device_id: String,
}

pub async fn logout(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<LogoutRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    auth_service::logout(&state.pool, &auth.phone, &req.device_id).await?;
    Ok(ok(serde_json::json!({})))
}

#[derive(Serialize)]
pub struct MeData {
    pub phone: String,
}

pub async fn me(auth: AuthUser) -> Result<Json<ApiResult<MeData>>, AppError> {
    Ok(ok(MeData { phone: auth.phone }))
}
