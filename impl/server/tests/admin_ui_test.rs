use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use server::config::Config;
use server::{AppState, build_router, db};
use std::sync::Arc;
use tower::ServiceExt;

// 管理页静态资源测试：dist/ 由 rust-embed 编译期嵌入，构建前先
// `cd admin-ui && npm run build`（dist/ 已提交仓库，常规检出即有）。

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
        chinadaily_base_url: "https://www.chinadaily.com.cn".into(),
        source_max_age_days: 3,
        source_fetch_timeout_secs: 15,
        recent_title_days: 14,
    }
}

#[tokio::test]
async fn admin_index_served_when_built() {
    // 编译期已保证 dist/ 存在（RustEmbed 缺失目录编译失败）；
    // 运行时再防御一次，缺 index.html 直接跳过断言。
    let dist_index = concat!(env!("CARGO_MANIFEST_DIR"), "/admin-ui/dist/index.html");
    if !std::path::Path::new(dist_index).exists() {
        eprintln!("admin-ui/dist 缺失：先执行 cd admin-ui && npm run build");
        return;
    }

    let db_path = format!("/tmp/ctx-admin-ui-{}.db", std::process::id());
    let cfg = Arc::new(test_cfg(&db_path));
    let pool = db::init_pool(&db_path).await.unwrap();
    let app = build_router(AppState {
        pool: pool.clone(),
        cfg,
    });

    // 1) GET /admin → 200 + text/html（index.html）
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/admin")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let ctype = resp
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();
    assert!(
        ctype.starts_with("text/html"),
        "content-type 应为 text/html，实际: {ctype}"
    );
    let body = resp.into_body().collect().await.unwrap().to_bytes();
    let html = String::from_utf8_lossy(&body);
    assert!(html.contains("id=\"app\""), "index.html 应含 #app 挂载点");

    // 2) SPA 回退：/admin/users（前端路由）→ 200 + index.html
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/admin/users")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    assert!(
        resp.headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .starts_with("text/html")
    );

    // 3) 静态资源：dist/assets/ 下首个 .js 文件 → 200 + text/javascript
    let assets_dir = concat!(env!("CARGO_MANIFEST_DIR"), "/admin-ui/dist/assets");
    if let Some(js) = std::fs::read_dir(assets_dir).ok().and_then(|entries| {
        entries
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .find(|n| n.ends_with(".js"))
    }) {
        let uri = format!("/admin/assets/{js}");
        let resp = app
            .clone()
            .oneshot(Request::builder().uri(&uri).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK, "资源 {uri} 应 200");
        assert!(
            resp.headers()
                .get("content-type")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .starts_with("text/javascript")
        );
    }

    // 4) API 前缀不受静态回退干扰：不存在的 API 路径仍 404（未吞 SPA 回退）
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/nonexistent")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    // 收尾：close 连接池 + 删临时库（防 WAL 残留）
    drop(app);
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}
