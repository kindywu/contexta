//! 文章下发 API（T10）：GET /api/articles/today、GET /api/articles?date=YYYY-MM-DD。
//! 仅已过审（approved）文章，需 App JWT（AuthUser）。无 date 参数时默认今日（Local 时区）。
//!
//! 段落序列化契约：App 端要求 `[{order_index, english_text, chinese_translation}]` 嵌套对象，
//! 而 article_service::ArticleView.paragraphs 是 `(order, en, zh)` 元组（Serialize 形状不符）——
//! 在路由层组装序列化值（ArticleJson），不动 article_service 的 ArticleView（T8 服务接口
//! 为 T11/T12 管理端复用，shape 保持内部形态）。

use axum::Json;
use axum::extract::{Query, State};
use chrono::Local;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::extractors::AuthUser;
use crate::response::{ApiResult, AppError, ok};
use crate::services::article_service;
use crate::services::article_service::ArticleView;

#[derive(Deserialize)]
pub struct ArticleQuery {
    pub date: Option<String>,
}

#[derive(Serialize)]
pub struct ParagraphJson {
    pub order_index: i64,
    pub english_text: String,
    pub chinese_translation: String,
}

#[derive(Serialize)]
pub struct ArticleJson {
    pub id: i64,
    pub target_date: String,
    pub difficulty: String,
    pub content_category: String,
    pub order_index: i64,
    pub title: String,
    pub status: String,
    pub regenerate_count: i64,
    pub paragraphs: Vec<ParagraphJson>,
}

impl From<ArticleView> for ArticleJson {
    fn from(v: ArticleView) -> Self {
        ArticleJson {
            id: v.id,
            target_date: v.target_date,
            difficulty: v.difficulty,
            content_category: v.content_category,
            order_index: v.order_index,
            title: v.title,
            status: v.status,
            regenerate_count: v.regenerate_count,
            paragraphs: v
                .paragraphs
                .into_iter()
                .map(|(o, en, zh)| ParagraphJson {
                    order_index: o,
                    english_text: en,
                    chinese_translation: zh,
                })
                .collect(),
        }
    }
}

/// 今日文章（Local 时区当天）。
pub async fn today(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<ApiResult<Vec<ArticleJson>>>, AppError> {
    let date = Local::now().format("%Y-%m-%d").to_string();
    let articles = article_service::get_approved_by_date(&state.pool, &date).await?;
    Ok(ok(articles.into_iter().map(ArticleJson::from).collect()))
}

/// 按日期文章；无 date 参数时默认今日。
pub async fn by_date(
    State(state): State<AppState>,
    _auth: AuthUser,
    Query(q): Query<ArticleQuery>,
) -> Result<Json<ApiResult<Vec<ArticleJson>>>, AppError> {
    let date = q
        .date
        .unwrap_or_else(|| Local::now().format("%Y-%m-%d").to_string());
    let articles = article_service::get_approved_by_date(&state.pool, &date).await?;
    Ok(ok(articles.into_iter().map(ArticleJson::from).collect()))
}
