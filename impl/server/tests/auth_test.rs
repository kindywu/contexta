use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{Value, json};
use server::db;
use server::{AppState, build_router, config::Config};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tower::ServiceExt;

// T2 审查遗留：同进程并行测试共享 `/tmp/ctx-auth-{pid}.db` 会碰撞，
// 用静态原子计数器给每个测试唯一后缀；收尾删除主文件 + -wal/-shm 侧车文件。
static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-auth-{}-{}.db", std::process::id(), n)
}

fn test_cfg(db_path: &str) -> Config {
    // 直接构造，避免依赖 env；JWT_SECRET 用固定值
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
        chinadaily_base_url: "https://www.chinadaily.com.cn".into(),
        source_max_age_days: 3,
        source_fetch_timeout_secs: 15,
        recent_title_days: 14,
    }
}

/// 收尾：drop 路由 → 显式 close 连接池（等待连接真正关闭，SQLite 清洁关闭会折掉 WAL）
/// → 删除主文件与 -wal/-shm 侧车文件。仅 drop 不 close 时，池的异步关连接任务
/// 可能与删除竞态（关连接时的 checkpoint 会重建 -wal/-shm），留下 /tmp 残留。
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
async fn login_registers_and_issues_token() {
    let (app, pool, db_path) = setup().await;
    let (status, json) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000001", "device_id": "dev-1"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(json["data"]["token"].as_str().unwrap().len() > 20);
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn second_device_evicts_oldest_when_two_active() {
    let (app, pool, db_path) = setup().await;
    let (_, j1) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000002", "device_id": "dev-a"}),
    )
    .await;
    let t1 = j1["data"]["token"].as_str().unwrap().to_string();
    let (_, j2) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000002", "device_id": "dev-b"}),
    )
    .await;
    let t2 = j2["data"]["token"].as_str().unwrap().to_string();
    // dev-a 仍在
    let (s1, _) = get_with_token(&app, "/api/auth/me", &t1).await;
    assert_eq!(s1, StatusCode::OK);
    // 第三台 dev-c → 挤掉 dev-a（最旧）
    let (_, j3) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000002", "device_id": "dev-c"}),
    )
    .await;
    let t3 = j3["data"]["token"].as_str().unwrap().to_string();
    let (s1, _) = get_with_token(&app, "/api/auth/me", &t1).await;
    assert_eq!(s1, StatusCode::UNAUTHORIZED, "oldest should be evicted");
    assert_eq!(
        json_get_code(&s1, &get_with_token(&app, "/api/auth/me", &t1).await.1),
        "EVICTED"
    );
    let (s2, _) = get_with_token(&app, "/api/auth/me", &t2).await;
    assert_eq!(s2, StatusCode::OK);
    let (s3, _) = get_with_token(&app, "/api/auth/me", &t3).await;
    assert_eq!(s3, StatusCode::OK);
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn same_device_relogin_replaces_own_session() {
    let (app, pool, db_path) = setup().await;
    for _ in 0..4 {
        let (_, j) = post(
            &app,
            "/api/auth/login",
            json!({"phone": "13800000003", "device_id": "dev-x"}),
        )
        .await;
        assert!(j["data"]["token"].as_str().is_some());
    }
    let (_, j) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000003", "device_id": "dev-y"}),
    )
    .await;
    let ty = j["data"]["token"].as_str().unwrap().to_string();
    let (s, _) = get_with_token(&app, "/api/auth/me", &ty).await;
    assert_eq!(s, StatusCode::OK);
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn relogin_refreshes_eviction_order() {
    let (app, pool, db_path) = setup().await;
    // A 登 → B 登 → A 重登（刷新 issued_at）→ C 登：应挤掉 B，保留最近活跃的 A 与 C
    let (_, j1) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000004", "device_id": "dev-a"}),
    )
    .await;
    let t1 = j1["data"]["token"].as_str().unwrap().to_string();
    let (_, j2) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000004", "device_id": "dev-b"}),
    )
    .await;
    let t2 = j2["data"]["token"].as_str().unwrap().to_string();
    let (_, j3) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000004", "device_id": "dev-a"}),
    )
    .await;
    let t3 = j3["data"]["token"].as_str().unwrap().to_string();
    let (_, j4) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000004", "device_id": "dev-c"}),
    )
    .await;
    let t4 = j4["data"]["token"].as_str().unwrap().to_string();
    // A 重登后的新 token 有效，B（未再活跃）被挤掉，C 有效
    let (s, _) = get_with_token(&app, "/api/auth/me", &t3).await;
    assert_eq!(s, StatusCode::OK, "relogined device should stay");
    let (s, j) = get_with_token(&app, "/api/auth/me", &t2).await;
    assert_eq!(
        s,
        StatusCode::UNAUTHORIZED,
        "inactive device should be evicted"
    );
    assert_eq!(j["error_code"], "EVICTED");
    let (s, _) = get_with_token(&app, "/api/auth/me", &t4).await;
    assert_eq!(s, StatusCode::OK);
    // A 的旧 token（重登前签发）同步失效
    let (s, j) = get_with_token(&app, "/api/auth/me", &t1).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    assert_eq!(j["error_code"], "EVICTED");
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn relogin_invalidates_old_token() {
    let (app, pool, db_path) = setup().await;
    let (_, j1) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000005", "device_id": "dev-1"}),
    )
    .await;
    let t1 = j1["data"]["token"].as_str().unwrap().to_string();
    let (_, j2) = post(
        &app,
        "/api/auth/login",
        json!({"phone": "13800000005", "device_id": "dev-1"}),
    )
    .await;
    let t2 = j2["data"]["token"].as_str().unwrap().to_string();
    // 旧 token：会话 issued_at 已被重登刷新（严格单调递增）→ iat 不匹配 → 401 EVICTED
    let (s, j) = get_with_token(&app, "/api/auth/me", &t1).await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    assert_eq!(j["error_code"], "EVICTED");
    // 新 token 有效
    let (s, _) = get_with_token(&app, "/api/auth/me", &t2).await;
    assert_eq!(s, StatusCode::OK);
    cleanup(app, pool, &db_path).await;
}

fn json_get_code(_s: &StatusCode, json: &Value) -> String {
    json["error_code"].as_str().unwrap_or("").to_string()
}
