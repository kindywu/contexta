//! Task 2：管理端 prompt 管理 API（GET /api/admin/prompts 列表 + PUT /api/admin/prompts/{key} 更新）。
//! 全部挂 AdminAuth（无 token → 401）。隔离模式与 admin_users_test 一致：
//! 唯一库路径 + migrate + seed_admin + build_router + 收尾 close + 清理三件套。

use axum::body::Body;
use axum::http::{Request, StatusCode};
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
    format!("/tmp/ctx-admin-prompts-{}-{}.db", std::process::id(), n)
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
        admin_init_password: Some("pw123".into()),
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

/// setup：migrate → seed_admin → build_router（与生产启动流程一致）。
async fn setup() -> (axum::Router, sqlx::SqlitePool, String) {
    let db_path = unique_db_path();
    let cfg = Arc::new(test_cfg(&db_path));
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    db::seed_admin(&pool, "pw123").await.unwrap();
    let app = build_router(AppState {
        pool: pool.clone(),
        cfg,
    });
    (app, pool, db_path)
}

/// 通用请求：method + uri + 可选 Bearer token + 可选 JSON body。
async fn send(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    let req = match body {
        Some(b) => builder
            .header("content-type", "application/json")
            .body(Body::from(b.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    };
    let resp = app.clone().oneshot(req).await.unwrap();
    let status = resp.status();
    let json: Value =
        serde_json::from_slice(&resp.into_body().collect().await.unwrap().to_bytes()).unwrap();
    (status, json)
}

/// admin 登录拿 token（admin_init_password=pw123）。
async fn admin_login(app: &axum::Router) -> String {
    let (status, json) = send(
        app,
        "POST",
        "/api/admin/login",
        None,
        Some(json!({"username": "admin", "password": "pw123"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    json["data"]["token"].as_str().unwrap().to_string()
}

/// GET /api/admin/prompts：migrate 种子后回 7 项（key/content/updated_at 齐备）。
#[tokio::test]
async fn prompts_list_returns_seven_seeded_items() {
    let (app, pool, db_path) = setup().await;
    let token = admin_login(&app).await;
    let (status, json) = send(&app, "GET", "/api/admin/prompts", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let data = json["data"].as_array().unwrap();
    assert_eq!(data.len(), 7, "应回 7 个 prompt");
    for p in data {
        assert!(!p["key"].as_str().unwrap().is_empty());
        assert!(!p["content"].as_str().unwrap().is_empty());
        assert!(p["updated_at"].is_i64());
    }
    cleanup(app, pool, &db_path).await;
}

/// PUT /api/admin/prompts/{key}：更新生效——GET 列表与库内直查均见新值，updated_at 刷新。
#[tokio::test]
async fn prompt_update_takes_effect() {
    let (app, pool, db_path) = setup().await;
    let token = admin_login(&app).await;
    let (status, json) = send(
        &app,
        "PUT",
        "/api/admin/prompts/article_common",
        Some(&token),
        Some(json!({"content": "MODIFIED BY ADMIN"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    // GET 列表应看到新值
    let (status, json) = send(&app, "GET", "/api/admin/prompts", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().unwrap();
    let updated = data.iter().find(|p| p["key"] == "article_common").unwrap();
    assert_eq!(updated["content"], "MODIFIED BY ADMIN");
    assert!(
        updated["updated_at"].as_i64().unwrap() > 0,
        "更新后 updated_at 必须刷新"
    );
    // 库内直查一致
    let content: String =
        sqlx::query_scalar("SELECT content FROM prompt WHERE key = 'article_common'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(content, "MODIFIED BY ADMIN");
    cleanup(app, pool, &db_path).await;
}

/// PUT 未知 key → 400 BAD_PARAM。
#[tokio::test]
async fn prompt_update_unknown_key_returns_400() {
    let (app, pool, db_path) = setup().await;
    let token = admin_login(&app).await;
    let (status, json) = send(
        &app,
        "PUT",
        "/api/admin/prompts/not_a_key",
        Some(&token),
        Some(json!({"content": "x"})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["error_code"], "BAD_PARAM");
    cleanup(app, pool, &db_path).await;
}

/// PUT 空内容 → 400 BAD_PARAM；原内容不变。
#[tokio::test]
async fn prompt_update_empty_content_returns_400() {
    let (app, pool, db_path) = setup().await;
    let token = admin_login(&app).await;
    let (status, json) = send(
        &app,
        "PUT",
        "/api/admin/prompts/article_common",
        Some(&token),
        Some(json!({"content": "   "})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["error_code"], "BAD_PARAM");
    let content: String =
        sqlx::query_scalar("SELECT content FROM prompt WHERE key = 'article_common'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(
        content.contains("You are an English language learning content creator."),
        "空内容更新不得改动原值"
    );
    cleanup(app, pool, &db_path).await;
}

/// 无 AdminAuth：GET/PUT 均 401。
#[tokio::test]
async fn prompts_require_admin_auth() {
    let (app, pool, db_path) = setup().await;
    let (status, _) = send(&app, "GET", "/api/admin/prompts", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = send(
        &app,
        "PUT",
        "/api/admin/prompts/article_common",
        None,
        Some(json!({"content": "x"})),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    cleanup(app, pool, &db_path).await;
}
