// Task 10：文章下发 API 集成测试（HTTP 层）。
// GET /api/articles/today、GET /api/articles?date=YYYY-MM-DD——仅已过审（approved）可见，
// 需 AuthUser（App JWT）。段落按 App 契约序列化为
// [{order_index, english_text, chinese_translation}]。
// 造数据直接 SQL 插 article/article_paragraph（approved + pending 混合，断言只回 approved）。
// 隔离模式与 auth_test 一致：唯一库路径 + 收尾 close + 清理三件套。

use axum::body::Body;
use axum::http::{Request, StatusCode};
use chrono::Local;
use http_body_util::BodyExt;
use serde_json::{Value, json};
use server::db;
use server::{AppState, build_router, config::Config};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tower::ServiceExt;

static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-articles-{}-{}.db", std::process::id(), n)
}

fn test_cfg(db_path: &str) -> Config {
    Config {
        port: 0,
        db_path: db_path.to_string(),
        jwt_secret: "test-secret".into(),
        deepseek_api_key: "sk-test".into(),
        deepseek_base_url: "https://api.deepseek.com".into(),
        deepseek_model: "deepseek-v4-flash".into(),
        word_quota_daily: 200,
        article_budget_daily: 100,
        cache_ttl_days: 30,
        cache_max_rows: 5000,
        daily_generate_hour: 3,
        admin_init_password: None,
        llm_timeout_secs: 90,
    }
}

/// 收尾：drop 路由 → 显式 close 连接池 → 删除主文件与 -wal/-shm 侧车文件。
async fn cleanup(app: axum::Router, pool: sqlx::SqlitePool, db_path: &str) {
    drop(app);
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

async fn setup() -> (axum::Router, sqlx::SqlitePool, String) {
    let db_path = unique_db_path();
    let cfg = Arc::new(test_cfg(&db_path));
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    let app = build_router(AppState {
        pool: pool.clone(),
        cfg,
    });
    (app, pool, db_path)
}

/// 通过登录接口拿 App token（同时落会话行，AuthUser 会话校验可通过）。
async fn login(app: &axum::Router, phone: &str) -> String {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"phone": phone, "device_id": "dev-articles"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    json["data"]["token"].as_str().unwrap().to_string()
}

/// GET 请求，token 为 None 时无 Authorization 头。
async fn get(app: &axum::Router, uri: &str, token: Option<&str>) -> (StatusCode, Value) {
    let mut builder = Request::builder().method("GET").uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    let resp = app
        .clone()
        .oneshot(builder.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    (status, json)
}

/// 直接 SQL 造一篇文章（任意 status）+ 2 段（`英文|||中文` 单列，与生成管线一致）。
async fn insert_article(
    pool: &sqlx::SqlitePool,
    date: &str,
    difficulty: &str,
    category: &str,
    order_index: i64,
    status: &str,
) -> i64 {
    let now = chrono::Utc::now().timestamp_millis();
    let id = sqlx::query(
        "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, regenerate_count, prompt_tokens, completion_tokens, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, ?, ?)",
    )
    .bind(date)
    .bind(difficulty)
    .bind(category)
    .bind(order_index)
    .bind(format!("{status} title {order_index}"))
    .bind(status)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await
    .unwrap()
    .last_insert_rowid();
    for i in 1..=2 {
        sqlx::query(
            "INSERT INTO article_paragraph (article_id, order_index, text) VALUES (?, ?, ?)",
        )
        .bind(id)
        .bind(i)
        .bind(format!(
            "English {order_index}-{i}|||中文 {order_index}-{i}"
        ))
        .execute(pool)
        .await
        .unwrap();
    }
    id
}

#[tokio::test]
async fn today_returns_only_approved() {
    let (app, pool, db_path) = setup().await;
    let today = Local::now().format("%Y-%m-%d").to_string();
    // 3 篇 approved + 2 篇 pending（title 非空，仅 status 区分——证明过滤依据是状态而非标题）
    let mut approved_ids = Vec::new();
    for i in 1..=3 {
        let id = insert_article(&pool, &today, "LOW", "DAILY_CONVERSATION", i, "approved").await;
        approved_ids.push(id);
    }
    for i in 4..=5 {
        insert_article(&pool, &today, "MEDIUM", "NEWS", i, "pending_review").await;
    }
    let token = login(&app, "13800001001").await;
    let (status, json) = get(&app, "/api/articles/today", Some(&token)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let data = json["data"].as_array().unwrap();
    assert_eq!(data.len(), 3, "只应下发已过审 3 篇");
    let ids: Vec<i64> = data.iter().map(|a| a["id"].as_i64().unwrap()).collect();
    for id in &approved_ids {
        assert!(ids.contains(id), "approved 文章 {id} 应被下发");
    }
    for a in data {
        assert_eq!(a["status"], "approved");
        assert_eq!(a["target_date"], today);
        let order = a["order_index"].as_i64().unwrap();
        let paras = a["paragraphs"].as_array().unwrap();
        assert_eq!(paras.len(), 2, "每篇应含 2 段");
        let p1 = &paras[0];
        assert_eq!(p1["order_index"], 1);
        assert_eq!(p1["english_text"], format!("English {order}-1"));
        assert_eq!(p1["chinese_translation"], format!("中文 {order}-1"));
        assert!(a["title"].as_str().unwrap().contains("approved"));
    }
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn date_param_filters() {
    let (app, pool, db_path) = setup().await;
    insert_article(
        &pool,
        "2026-08-14",
        "LOW",
        "DAILY_CONVERSATION",
        1,
        "approved",
    )
    .await;
    insert_article(
        &pool,
        "2026-08-14",
        "LOW",
        "SCENE_DESCRIPTION",
        2,
        "approved",
    )
    .await;
    insert_article(&pool, "2026-08-14", "MEDIUM", "NEWS", 3, "pending_review").await;
    insert_article(
        &pool,
        "2026-08-15",
        "LOW",
        "DAILY_CONVERSATION",
        1,
        "approved",
    )
    .await;
    let token = login(&app, "13800001002").await;
    let (status, json) = get(&app, "/api/articles?date=2026-08-14", Some(&token)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let data = json["data"].as_array().unwrap();
    assert_eq!(data.len(), 2, "只应回 2026-08-14 的已过审 2 篇");
    for a in data {
        assert_eq!(a["status"], "approved");
        assert_eq!(a["target_date"], "2026-08-14");
        assert_eq!(a["paragraphs"].as_array().unwrap().len(), 2);
    }
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn requires_auth() {
    let (app, pool, db_path) = setup().await;
    let today = Local::now().format("%Y-%m-%d").to_string();
    insert_article(&pool, &today, "LOW", "DAILY_CONVERSATION", 1, "approved").await;
    let (status, json) = get(&app, "/api/articles/today", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(json["error_code"], "TOKEN_EXPIRED");
    let (status, _) = get(&app, "/api/articles?date=2026-08-14", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    cleanup(app, pool, &db_path).await;
}
