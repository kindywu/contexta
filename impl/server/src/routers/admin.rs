use crate::AppState;
use crate::response::{ApiResult, AppError, ok};
use crate::services::admin_service;
use axum::Json;
use axum::extract::State;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct AdminLoginRequest {
    pub username: String,
    pub password: String,
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<AdminLoginRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let token = admin_service::login(&state.pool, &state.cfg, &req.username, &req.password).await?;
    Ok(ok(serde_json::json!({ "token": token })))
}

// 用户管理路由由 Task 11 填充；此处先挂占位返回空数组（AdminAuth 已校验）
pub async fn users_list(
    _: crate::extractors::AdminAuth,
) -> Result<Json<ApiResult<Vec<serde_json::Value>>>, AppError> {
    Ok(ok(vec![]))
}
