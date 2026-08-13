// Task 12：管理 API（文章审核）集成测试（HTTP 层）。
// GET /api/admin/articles（status/date 筛选）、GET /api/admin/articles/{id}（含段落）、
// POST approve（→ approved，今日下发可见）、POST reject（原行 rejected + 新行 pending_review，
// regenerate_count=1；连续 4 次 → rejected_final 不再新增）、POST generate（手动生成，幂等）、
// App token 访问管理端点 → 401。
// 造 15 篇：直接调 ensure_daily_generation + MockArticleApi（T8 模式，无网络）；reject/generate
// 端点内部构造 DeepSeekClient（简报注入模式）→ httpmock 拦截 LLM 调用返回合法文章 XML
// （deepseek_test 模式）。隔离模式与 admin_users_test 一致：唯一库路径 + 收尾 close + 清理三件套。

use async_trait::async_trait;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{Value, json};
use server::db;
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::services::article_service;
use server::{AppState, build_router, config::Config};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tower::ServiceExt;

static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-admin-articles-{}-{}.db", std::process::id(), n)
}

fn test_cfg(db_path: &str, base_url: &str) -> Config {
    Config {
        port: 0,
        db_path: db_path.to_string(),
        jwt_secret: "test-secret".into(),
        deepseek_api_key: "sk-test".into(),
        deepseek_base_url: base_url.into(),
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
/// （沿用 admin_users_test 加固模式）。
async fn cleanup(app: axum::Router, pool: sqlx::SqlitePool, db_path: &str) {
    drop(app);
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

/// 注册 LLM 拦截 mock：POST /v1/chat/completions → 合法文章 XML（parse_article 可解析）。
/// Mock 无 Drop 注销（httpmock 0.8：仅 MockServer drop / Mock::delete 注销），返回句柄可丢弃。
fn register_llm_mock(server: &httpmock::MockServer) {
    server.mock(|when, then| {
        when.method(httpmock::Method::POST).path("/v1/chat/completions");
        then.status(200)
            .header("content-type", "application/json")
            .body(
                json!({
                    "choices": [{"message": {"content": "<title>MockT</title><paragraph>P1.</paragraph><translation>译1。</translation>"}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1},
                })
                .to_string(),
            );
    });
}

/// setup：httpmock 拦 LLM → migrate → seed_admin → build_router（与生产启动流程一致）。
async fn setup() -> (
    axum::Router,
    sqlx::SqlitePool,
    Arc<Config>,
    String,
    httpmock::MockServer,
) {
    let server = httpmock::MockServer::start();
    register_llm_mock(&server);
    let db_path = unique_db_path();
    let cfg = Arc::new(test_cfg(&db_path, &server.base_url()));
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    db::seed_admin(&pool, "pw123").await.unwrap();
    let app = build_router(AppState {
        pool: pool.clone(),
        cfg: cfg.clone(),
    });
    (app, pool, cfg, db_path, server)
}

/// 通用请求：method + uri + 可选 Bearer token + 可选 JSON body（admin_users_test 模式）。
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
        Some(json!({"phone": phone, "device_id": "dev-admin-articles"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    json["data"]["token"].as_str().unwrap().to_string()
}

// mock DeepSeek（T8 模式）：用户 prompt 含分类名；返回含分类名的合法文章 XML
// （<title>/<paragraph>/<translation> 齐备，parse_article 可解析）。仅用于造数直调，
// 不走网络；HTTP 端点的 LLM 调用由 httpmock 拦截。
struct MockArticleApi;
#[async_trait]
impl DeepSeekApi for MockArticleApi {
    async fn chat(&self, _s: &str, u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        Ok(DeepSeekResponse {
            content: format!(
                "<title>T{u}</title><paragraph>P1.</paragraph><translation>译1。</translation>"
            ),
            prompt_tokens: 1,
            completion_tokens: 1,
        })
    }
}

#[tokio::test]
async fn list_and_review_flow() {
    let (app, pool, cfg, db_path, _server) = setup().await;
    let admin_token = admin_login(&app).await;
    // 造 15 篇（ensure_daily_generation + mock api）。approve 后要验证「今日下发可见」，
    // 故用本地今日日期（GET /api/articles/today 只回本地今日 approved 文章）。
    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, &today)
        .await
        .unwrap();
    // 待审列表：status + date 筛选 → 15 篇，title 非空（已生成），含段落
    let uri = format!("/api/admin/articles?status=pending_review&date={today}");
    let (status, json) = send(&app, "GET", &uri, Some(&admin_token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let data = json["data"].as_array().unwrap();
    assert_eq!(data.len(), 15, "待审应 15 篇");
    let a = &data[0];
    assert_eq!(a["status"], "pending_review");
    assert_eq!(a["target_date"], today);
    assert!(
        !a["title"].as_str().unwrap().is_empty(),
        "已生成文章 title 非空"
    );
    assert!(
        !a["paragraphs"].as_array().unwrap().is_empty(),
        "列表项应含段落"
    );
    // 详情：含段落，英文/中文已拆分
    let id = a["id"].as_i64().unwrap();
    let (status, json) = send(
        &app,
        "GET",
        &format!("/api/admin/articles/{id}"),
        Some(&admin_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"]["id"], id);
    assert_eq!(json["data"]["paragraphs"][0][1], "P1.");
    assert_eq!(json["data"]["paragraphs"][0][2], "译1。");
    // approve → status=approved；今日下发可见（App token 调 /api/articles/today）
    let user_token = user_login(&app, "13800001201").await;
    let (status, json) = send(
        &app,
        "POST",
        &format!("/api/admin/articles/{id}/approve"),
        Some(&admin_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let (status, json) = send(&app, "GET", "/api/articles/today", Some(&user_token), None).await;
    assert_eq!(status, StatusCode::OK);
    let today_list = json["data"].as_array().unwrap();
    assert_eq!(today_list.len(), 1, "仅已过审的 1 篇今日可见");
    assert_eq!(today_list[0]["id"], id);
    assert_eq!(today_list[0]["paragraphs"][0]["english_text"], "P1.");
    // reject 另一篇 {reason} → 原行 rejected（reason 落库）+ 新行 pending_review
    // （regenerate_count=1，补生成经 httpmock 填充）
    let id2 = data[1]["id"].as_i64().unwrap();
    let (status, json) = send(
        &app,
        "POST",
        &format!("/api/admin/articles/{id2}/reject"),
        Some(&admin_token),
        Some(json!({"reason": "质量差"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let old_status: String = sqlx::query_scalar("SELECT status FROM article WHERE id = ?")
        .bind(id2)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(old_status, "rejected");
    let reason: String = sqlx::query_scalar("SELECT reject_reason FROM article WHERE id = ?")
        .bind(id2)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(reason, "质量差", "reject_reason 应落库");
    let new_id: i64 = sqlx::query_scalar("SELECT MAX(id) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(new_id > id2, "补生成应产生新行");
    let (st, regen): (String, i64) =
        sqlx::query_as("SELECT status, regenerate_count FROM article WHERE id = ?")
            .bind(new_id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(st, "pending_review");
    assert_eq!(regen, 1, "补生成行 regenerate_count=1");
    // 拒绝后待审 14 篇（15 − approve 1 − reject 1 + 补生成 1）；status=rejected 筛出 1 篇
    let (status, json) = send(&app, "GET", &uri, Some(&admin_token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        json["data"].as_array().unwrap().len(),
        14,
        "拒绝后补 1 篇，待审 14（15 − approve 1 − reject 1 + 补 1）"
    );
    let (status, json) = send(
        &app,
        "GET",
        &format!("/api/admin/articles?status=rejected&date={today}"),
        Some(&admin_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let rej = json["data"].as_array().unwrap();
    assert_eq!(rej.len(), 1, "status=rejected 应筛出 1 篇");
    assert_eq!(rej[0]["id"], id2);
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn reject_until_cap_marks_final() {
    let (app, pool, cfg, db_path, _server) = setup().await;
    let admin_token = admin_login(&app).await;
    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, &today)
        .await
        .unwrap();
    let first: i64 = sqlx::query_scalar("SELECT id FROM article ORDER BY id LIMIT 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    // 连续 4 次 reject（HTTP，补生成走 httpmock）：前 3 次各补 1 行（regenerate_count=1/2/3），
    // 第 4 次 → rejected_final 且不再新增
    let mut cur = first;
    for k in 1..=4 {
        let (status, json) = send(
            &app,
            "POST",
            &format!("/api/admin/articles/{cur}/reject"),
            Some(&admin_token),
            Some(json!({"reason": "bad"})),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "第 {k} 次 reject 应成功");
        assert_eq!(json["code"], 0);
        let st: String = sqlx::query_scalar("SELECT status FROM article WHERE id = ?")
            .bind(cur)
            .fetch_one(&pool)
            .await
            .unwrap();
        if k == 4 {
            assert_eq!(st, "rejected_final", "第 4 次 reject 后该分支终态");
        } else {
            assert_eq!(st, "rejected", "第 {k} 次 reject 后父行 rejected");
            let m: i64 = sqlx::query_scalar("SELECT MAX(id) FROM article")
                .fetch_one(&pool)
                .await
                .unwrap();
            assert!(m > cur, "第 {k} 次 reject 应产生新行");
            let (st2, regen2): (String, i64) =
                sqlx::query_as("SELECT status, regenerate_count FROM article WHERE id = ?")
                    .bind(m)
                    .fetch_one(&pool)
                    .await
                    .unwrap();
            assert_eq!(st2, "pending_review");
            assert_eq!(regen2, k as i64, "第 {k} 次补生成 regenerate_count");
            cur = m;
        }
    }
    let m: i64 = sqlx::query_scalar("SELECT MAX(id) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(m, cur, "第 4 次 reject 后不得新增行");
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn manual_generate_for_date() {
    // 本测试需要 LLM mock 句柄断言调用次数（幂等 = 重复调用零 LLM 消耗），自建环境
    let server = httpmock::MockServer::start();
    let llm = server.mock(|when, then| {
        when.method(httpmock::Method::POST).path("/v1/chat/completions");
        then.status(200)
            .header("content-type", "application/json")
            .body(
                json!({
                    "choices": [{"message": {"content": "<title>MockT</title><paragraph>P1.</paragraph><translation>译1。</translation>"}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1},
                })
                .to_string(),
            );
    });
    let db_path = unique_db_path();
    let cfg = Arc::new(test_cfg(&db_path, &server.base_url()));
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    db::seed_admin(&pool, "pw123").await.unwrap();
    let app = build_router(AppState {
        pool: pool.clone(),
        cfg,
    });
    let admin_token = admin_login(&app).await;
    // 非法日期（"abc"/非零填充 "2026-8-14"）→ 400 BAD_PARAM，且零写入、零 LLM 调用
    // （否则垃圾 target_date 静默入库 15 行，消耗预算 + LLM 成本且永久滞留）
    for bad in ["abc", "2026-8-14"] {
        let (status, json) = send(
            &app,
            "POST",
            "/api/admin/articles/generate",
            Some(&admin_token),
            Some(json!({"date": bad})),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "非法日期 {bad} 应 400");
        assert_eq!(json["error_code"], "BAD_PARAM");
    }
    let total0: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total0, 0, "非法日期不得产生任何行");
    llm.assert_calls(0);
    // 手动生成指定日期 → 15 篇（每难度 5）全部填充（LLM 走 httpmock）
    let (status, json) = send(
        &app,
        "POST",
        "/api/admin/articles/generate",
        Some(&admin_token),
        Some(json!({"date": "2026-08-14"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total, 15, "手动生成应产出 15 篇");
    let filled: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM article WHERE status = 'pending_review' AND title IS NOT NULL",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(filled, 15, "15 篇全部填充（预占行 + LLM 出稿）");
    // 幂等：重复调用不新增（且无新的 LLM 调用）
    let (status, json) = send(
        &app,
        "POST",
        "/api/admin/articles/generate",
        Some(&admin_token),
        Some(json!({"date": "2026-08-14"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    let total2: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total2, 15, "重复手动生成必须幂等");
    llm.assert_calls(15);
    cleanup(app, pool, &db_path).await;
}

#[tokio::test]
async fn app_token_cannot_access_admin() {
    let (app, pool, _cfg, db_path, _server) = setup().await;
    // App token（普通用户登录）调管理端点 → 401
    let user_token = user_login(&app, "13800001202").await;
    let (status, json) = send(&app, "GET", "/api/admin/articles", Some(&user_token), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(json["code"], 401);
    // 无 token → 401
    let (status, _) = send(&app, "GET", "/api/admin/articles", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // 管理 token 正常访问（空列表，正控）
    let admin_token = admin_login(&app).await;
    let (status, json) = send(&app, "GET", "/api/admin/articles", Some(&admin_token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["code"], 0);
    assert!(json["data"].as_array().unwrap().is_empty());
    cleanup(app, pool, &db_path).await;
}
