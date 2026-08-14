use crate::AppState;
use crate::drivers::deepseek::DeepSeekClient;
use crate::extractors::AdminAuth;
use crate::response::{ApiResult, AppError, ok};
use crate::services::{admin_service, article_service, prompt_service};
use axum::Json;
use axum::extract::{Path, Query, State};
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

// ---------- 文章审核（T12） ----------
// 全部挂 AdminAuth。列表/详情 title 语义：空串 = 预占/生成中/失败，管理页显示时处理
// （T13 显示「生成中」），本层不改变字段语义。

#[derive(Deserialize)]
pub struct ArticleListQuery {
    pub date: Option<String>,
    pub status: Option<String>,
}

#[derive(Deserialize)]
pub struct ArticleRejectRequest {
    pub reason: Option<String>,
}

#[derive(Deserialize)]
pub struct ArticleGenerateRequest {
    pub date: String,
}

#[derive(Deserialize)]
pub struct ArticleEditRequest {
    pub title: String,
    pub paragraphs: Vec<ParagraphEditItem>,
}

#[derive(Deserialize)]
pub struct ParagraphEditItem {
    pub order_index: i64,
    pub english_text: String,
    pub chinese_translation: String,
}

/// 待审列表：status/date 可选过滤（article_service::list_articles 白名单列 + 全绑参）。
pub async fn articles_list(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Query(q): Query<ArticleListQuery>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let rows =
        article_service::list_articles(&state.pool, q.date.as_deref(), q.status.as_deref()).await?;
    Ok(ok(serde_json::to_value(rows)?))
}

/// 文章详情（含段落，英文/中文已拆分）。
pub async fn articles_get(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(id): Path<i64>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let view = article_service::get_article(&state.pool, id).await?;
    Ok(ok(serde_json::to_value(view)?))
}

/// 审核期文章编辑：仅已生成 pending_review（status + title IS NOT NULL 双守卫）；
/// title 非空、paragraphs ≥1、每段 en/zh 至少一个非空（校验失败 400），其余
/// （不存在/预占/已过审/已拒绝）→ 404。段落 order_index 由服务端按请求序重编（忽略客户端值）。
pub async fn article_edit(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(id): Path<i64>,
    Json(req): Json<ArticleEditRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let paras: Vec<(i64, String, String)> = req
        .paragraphs
        .into_iter()
        .map(|p| (p.order_index, p.english_text, p.chinese_translation))
        .collect();
    article_service::update_article_content(&state.pool, id, &req.title, &paras).await?;
    Ok(ok(serde_json::json!({})))
}

/// 审核通过：status → approved（仅已生成行可过审，预占/生成中行 404）。
pub async fn articles_approve(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(id): Path<i64>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    article_service::approve_article(&state.pool, id).await?;
    Ok(ok(serde_json::json!({})))
}

/// 审核拒绝：原行 → rejected（reason 落库），内部触发补生成（未达上限时新行 pending_review，
/// 达到 REGENERATE_CAP 则 rejected_final）；补生成 LLM 调用由本层注入 DeepSeekClient。
pub async fn articles_reject(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(id): Path<i64>,
    Json(req): Json<ArticleRejectRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let client = DeepSeekClient::new(&state.cfg)?;
    article_service::reject_article(
        &state.pool,
        &state.cfg,
        &client,
        id,
        req.reason.as_deref().unwrap_or(""),
    )
    .await?;
    Ok(ok(serde_json::json!({})))
}

// ---------- Prompt 管理（Task 2） ----------
// 全部挂 AdminAuth。GET 全量列表（key/content/updated_at）；PUT 单 key 更新
// （白名单 + 非空校验，失败 400 BAD_PARAM；成功后运行时立即生效——LLM 调用逐次读库）。

#[derive(Deserialize)]
pub struct PromptUpdateRequest {
    pub content: String,
}

/// prompt 列表：7 个 key 的 content + updated_at（updated_at=0 表示种子默认）。
pub async fn prompts_list(
    State(state): State<AppState>,
    _auth: AdminAuth,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let rows = prompt_service::get_all_prompts(&state.pool).await?;
    Ok(ok(serde_json::to_value(rows)?))
}

/// 更新单 key：白名单校验（未知 key 400）+ 非空校验（400），UPSERT 刷新 updated_at。
pub async fn prompt_update(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Path(key): Path<String>,
    Json(req): Json<PromptUpdateRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    prompt_service::update_prompt(&state.pool, &key, &req.content).await?;
    Ok(ok(serde_json::json!({})))
}

/// 手动补生成指定日期：ensure_daily_generation（幂等，预占行模式）。
/// 日期先严格校验（垃圾日期原样入库会静默产出 15 行垃圾 target_date，消耗当日预算 +
/// 15 次 LLM 成本且行永久滞留），失败 → 400 BAD_PARAM。chrono 的 %m/%d 容忍非零填充
/// （"2026-8-14" 能解析），故用「解析 → 按 %Y-%m-%d 回格式化 → 与输入全等」收紧为
/// 严格零填充 ISO 格式，同时天然拒绝非法月日（"2026-13-01"/"2026-02-30"）。
pub async fn articles_generate(
    State(state): State<AppState>,
    _auth: AdminAuth,
    Json(req): Json<ArticleGenerateRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let strict_iso = chrono::NaiveDate::parse_from_str(&req.date, "%Y-%m-%d")
        .map(|d| d.format("%Y-%m-%d").to_string() == req.date)
        .unwrap_or(false);
    if !strict_iso {
        return Err(AppError::BadRequest(
            "BAD_PARAM".into(),
            "invalid date".into(),
        ));
    }
    let client = DeepSeekClient::new(&state.cfg)?;
    article_service::ensure_daily_generation(&state.pool, &state.cfg, &client, &req.date).await?;
    Ok(ok(serde_json::json!({})))
}
