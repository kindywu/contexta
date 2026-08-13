use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{Value, json};
use server::db;
use server::{AppState, build_router, config::Config};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tower::ServiceExt;

// T2 审查遗留：同进程并行测试共享 /tmp 路径会碰撞，用静态原子计数器给每个测试唯一后缀；
// 收尾删除主文件 + -wal/-shm 侧车文件（沿用 auth_test 的 T3 加固模式）。
static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-admin-{}-{}.db", std::process::id(), n)
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

/// 收尾：drop 路由 → 显式 close 连接池（等待连接真正关闭，SQLite 清洁关闭会折掉 WAL）
/// → 删除主文件与 -wal/-shm 侧车文件（沿用 auth_test 加固模式，防关连接 checkpoint 竞态残留）。
async fn cleanup(app: axum::Router, pool: sqlx::SqlitePool, db_path: &str) {
    drop(app);
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

/// setup：migrate → seed_admin（与生产启动流程一致）→ build_router。
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

async fn post(app: &axum::Router, uri: &str, body: Value) -> (StatusCode, Value) {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let json: Value =
        serde_json::from_slice(&resp.into_body().collect().await.unwrap().to_bytes()).unwrap();
    (status, json)
}

async fn get_with_token(app: &axum::Router, uri: &str, token: &str) -> (StatusCode, Value) {
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let json: Value =
        serde_json::from_slice(&resp.into_body().collect().await.unwrap().to_bytes()).unwrap();
    (status, json)
}

#[tokio::test]
async fn admin_login_and_app_token_rejected() {
    let (app, pool, db_path) = setup().await;
    // 1) 错误密码 → 401 + TOKEN_EXPIRED
    let (status, json) = post(
        &app,
        "/api/admin/login",
        json!({"username": "admin", "password": "wrong"}),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(json["error_code"], "TOKEN_EXPIRED");
    // 2) 正确密码 → data.token 非空
    let (status, json) = post(
        &app,
        "/api/admin/login",
        json!({"username": "admin", "password": "pw123"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let admin_token = json["data"]["token"].as_str().unwrap().to_string();
    assert!(admin_token.len() > 20);
    // 3) 普通 App token（先 login 拿）访问 /api/admin/users → 401
    let (_, j) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000001", "device_id": "dev-1"}),
    )
    .await;
    let app_token = j["data"]["token"].as_str().unwrap().to_string();
    let (status, _) = get_with_token(&app, "/api/admin/users", &app_token).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // 4) admin token 访问 /api/admin/users → 200，data 为数组（占位空列表）
    let (status, json) = get_with_token(&app, "/api/admin/users", &admin_token).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json["data"].is_array(), "data should be an array");
    cleanup(app, pool, &db_path).await;
}
