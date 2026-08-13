use crate::AppState;
use crate::extractors::AdminAuth;
use crate::response::{ApiResult, AppError, ok};
use crate::services::admin_service;
use axum::Json;
use axum::extract::{Path, State};
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

#[derive(Deserialize)]
pub struct BanRequest {
    pub reason: Option<String>,
}

#[derive(Deserialize)]
pub struct SetQuotaRequest {
    pub word_daily: Option<i64>,
}

/// 用户列表（含今日查词用量）。全部管理端点挂 AdminAuth 校验。
pub async fn users_list(
    State(state): State<AppState>,
    _auth: AdminAuth,
) -> Result<Json<ApiResult<Vec<serde_json::Value>>>, AppError> {
    let users = admin_service::list_users(&state.pool).await?;
    Ok(ok(users))
}

/// 封禁：status → banned，记录 reason。
pub async fn ban(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(phone): Path<String>,
    Json(req): Json<BanRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    admin_service::set_status(&state.pool, &phone, "banned", req.reason.as_deref()).await?;
    Ok(ok(serde_json::json!({})))
}

/// 解封：status → normal，清空 reason。
pub async fn unban(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(phone): Path<String>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    admin_service::set_status(&state.pool, &phone, "normal", None).await?;
    Ok(ok(serde_json::json!({})))
}

/// 配额覆盖：word_daily 为 null 时清覆盖（回落全局默认）。
pub async fn set_quota(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(phone): Path<String>,
    Json(req): Json<SetQuotaRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    admin_service::set_quota(&state.pool, &phone, req.word_daily).await?;
    Ok(ok(serde_json::json!({})))
}

/// 今日用量汇总（按 phone × endpoint 聚合 token）。
pub async fn usage(
    State(state): State<AppState>,
    _auth: AdminAuth,
) -> Result<Json<ApiResult<Vec<serde_json::Value>>>, AppError> {
    let report = admin_service::usage_report(&state.pool).await?;
    Ok(ok(report))
}
