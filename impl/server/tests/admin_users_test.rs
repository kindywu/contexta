// Task 11：管理 API（用户管理 + 用量）集成测试（HTTP 层）。
// GET /api/admin/users（列表含今日查词）、POST ban/unban、PUT quota、GET /api/admin/usage。
// 造数据直接 SQL 插 users（登录自动注册）/ usage_log（控制 created_at 跨今日/昨日边界）。
// 隔离模式与 admin_auth_test 一致：唯一库路径 + 收尾 close + 清理三件套。

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{Value, json};
use server::db;
use server::response::AppError;
use server::services::llm_service;
use server::services::today_start_millis;
use server::{AppState, build_router, config::Config};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tower::ServiceExt;

static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-admin-users-{}-{}.db", std::process::id(), n)
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

/// 收尾：drop 路由 → 显式 close 连接池 → 删除主文件与 -wal/-shm 侧车文件
/// （沿用 admin_auth_test 加固模式）。
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

/// 用户登录（自动注册）拿 token。
async fn user_login(app: &axum::Router, phone: &str) -> String {
    let (status, json) = send(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({"phone": phone, "device_id": "dev-admin-users"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    json["data"]["token"].as_str().unwrap().to_string()
}

/// 直接 SQL 插一条 usage_log（created_at 可控，跨今日/昨日边界）。
async fn insert_usage(
    pool: &sqlx::SqlitePool,
    phone: &str,
    endpoint: &str,
    prompt_tokens: i64,
    completion_tokens: i64,
    created_at: i64,
) {
    sqlx::query(
        "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at)
         VALUES (?, ?, ?, ?, 0, ?)",
    )
    .bind(phone)
    .bind(endpoint)
    .bind(prompt_tokens)
    .bind(completion_tokens)
    .bind(created_at)
    .execute(pool)
    .await
    .unwrap();
}

#[tokio::test]
async fn list_users_with_daily_usage() {
    let (app, pool, db_path) = setup().await;
    let admin_token = admin_login(&app).await;
    let a = "13800001101";
    let b = "13800001102";
    user_login(&app, a).await;
    user_login(&app, b).await;
    let start = today_start_millis();
    // A：今日 1 次查词 + 昨日 2 次（昨日不计入 today_word_lookups）
    insert_usage(&pool, a, "word_lookup", 10, 5, start + 1).await;
    insert_usage(&pool, a, "word_lookup", 10, 5, start - 86_400_000).await;
    insert_usage(&pool, a, "word_lookup", 10, 5, start - 2 * 86_400_000).await;
    // B：今日 3 次
    insert_usage(&pool, b, "word_lookup", 10, 5, start + 1).await;
    insert_usage(&pool, b, "word_lookup", 10, 5, start + 2).await;
    insert_usage(&pool, b, "word_lookup", 10, 5, start + 3).await;
    let (status, json) = send(&app, "GET", "/api/admin/users", Some(&admin_token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let data = json["data"].as_array().unwrap();
    assert_eq!(data.len(), 2, "应回 2 个用户");
    let by_phone: HashMap<&str, &Value> = data
        .iter()
        .map(|u| (u["phone"].as_str().unwrap(), u))
        .collect();
    for phone in [a, b] {
        let u = by_phone[phone];
        assert_eq!(u["status"], "normal");
        assert!(u["created_at"].as_i64().unwrap() > 0);
        assert!(u["quota_word_daily"].is_null(), "未覆盖配额应为 null");
        assert!(u["banned_reason"].is_null(), "未封禁 reason 应为 null");
    }
    assert_eq!(
        by_phone[a]["today_word_lookups"], 1,
        "A 今日 1 次，昨日不计"
    );
    assert_eq!(by_phone[b]["today_word_lookups"], 3, "B 今日 3 次");
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn ban_and_unban_blocks_login_and_requests() {
    let (app, pool, db_path) = setup().await;
    let admin_token = admin_login(&app).await;
    let phone = "13800001104";
    // 先登录拿 token（会话行落库，验证封禁后既有会话也被拒）
    let user_token = user_login(&app, phone).await;
    // 封禁（带 reason）
    let (status, json) = send(
        &app,
        "POST",
        &format!("/api/admin/users/{phone}/ban"),
        Some(&admin_token),
        Some(json!({"reason": "滥用"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    // 既有 token 请求被拒：403 BANNED
    let (status, json) = send(&app, "GET", "/api/auth/me", Some(&user_token), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(json["error_code"], "BANNED");
    // 新登录也被拒：403 BANNED
    let (status, json) = send(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({"phone": phone, "device_id": "dev-2"})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(json["error_code"], "BANNED");
    // 列表应显示 banned + reason
    let (status, json) = send(&app, "GET", "/api/admin/users", Some(&admin_token), None).await;
    assert_eq!(status, StatusCode::OK);
    let u = json["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["phone"] == phone)
        .unwrap();
    assert_eq!(u["status"], "banned");
    assert_eq!(u["banned_reason"], "滥用");
    // 解封 → 登录恢复
    let (status, json) = send(
        &app,
        "POST",
        &format!("/api/admin/users/{phone}/unban"),
        Some(&admin_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let (status, json) = send(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({"phone": phone, "device_id": "dev-3"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(json["data"]["token"].as_str().unwrap().len() > 20);
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn set_quota_override() {
    let (app, pool, db_path) = setup().await;
    let cfg = test_cfg(&db_path);
    let admin_token = admin_login(&app).await;
    let phone = "13800001103";
    user_login(&app, phone).await;
    // 今日 6 次查词
    let start = today_start_millis();
    for i in 0..6 {
        insert_usage(&pool, phone, "word_lookup", 10, 5, start + i).await;
    }
    // 全局默认配额 200 → 6 < 200 通过
    assert!(
        llm_service::check_quota(&pool, &cfg, phone).await.is_ok(),
        "默认配额下 6 次不应被拒"
    );
    // PUT quota {word_daily: 5} → 6 >= 5 被拒（复用 llm_service::check_quota 断言）
    let (status, json) = send(
        &app,
        "PUT",
        &format!("/api/admin/users/{phone}/quota"),
        Some(&admin_token),
        Some(json!({"word_daily": 5})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let err = llm_service::check_quota(&pool, &cfg, phone)
        .await
        .unwrap_err();
    assert!(
        matches!(err, AppError::QuotaExceeded(_)),
        "覆盖为 5 后 6 次应 QuotaExceeded"
    );
    // 清空覆盖（null）→ 回落全局默认 → 通过
    let (status, _) = send(
        &app,
        "PUT",
        &format!("/api/admin/users/{phone}/quota"),
        Some(&admin_token),
        Some(json!({"word_daily": null})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        llm_service::check_quota(&pool, &cfg, phone).await.is_ok(),
        "清空覆盖后应回落全局默认"
    );
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn usage_report() {
    let (app, pool, db_path) = setup().await;
    let admin_token = admin_login(&app).await;
    let a = "13800001105";
    let b = "13800001106";
    user_login(&app, a).await;
    user_login(&app, b).await;
    let start = today_start_millis();
    // A 今日：word_lookup×2（prompt 10+20=30, completion 5+7=12）、article_generate×1（100/50）
    insert_usage(&pool, a, "word_lookup", 10, 5, start + 1).await;
    insert_usage(&pool, a, "word_lookup", 20, 7, start + 2).await;
    insert_usage(&pool, a, "article_generate", 100, 50, start + 3).await;
    // B 今日：word_lookup×1（33/44）
    insert_usage(&pool, b, "word_lookup", 33, 44, start + 1).await;
    // A 昨日 1 条（999/999）→ 不计入今日报告
    insert_usage(&pool, a, "word_lookup", 999, 999, start - 86_400_000).await;
    let (status, json) = send(&app, "GET", "/api/admin/usage", Some(&admin_token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let data = json["data"].as_array().unwrap();
    assert_eq!(data.len(), 3, "按 (phone, endpoint) 应 3 组，昨日不计入");
    let key = |r: &Value| {
        format!(
            "{}|{}",
            r["phone"].as_str().unwrap(),
            r["endpoint"].as_str().unwrap()
        )
    };
    let by_key: HashMap<String, &Value> = data.iter().map(|r| (key(r), r)).collect();
    let a_wl = by_key[&format!("{a}|word_lookup")];
    assert_eq!(a_wl["calls"], 2);
    assert_eq!(a_wl["prompt_tokens"], 30);
    assert_eq!(a_wl["completion_tokens"], 12);
    let a_ag = by_key[&format!("{a}|article_generate")];
    assert_eq!(a_ag["calls"], 1);
    assert_eq!(a_ag["prompt_tokens"], 100);
    assert_eq!(a_ag["completion_tokens"], 50);
    let b_wl = by_key[&format!("{b}|word_lookup")];
    assert_eq!(b_wl["calls"], 1);
    assert_eq!(b_wl["prompt_tokens"], 33);
    assert_eq!(b_wl["completion_tokens"], 44);
    // 昨日 999 的 token 不应出现在任何分组
    for r in data {
        assert_ne!(r["prompt_tokens"], 999, "昨日数据不得计入");
    }
    cleanup(app, pool, &db_path).await;
}
