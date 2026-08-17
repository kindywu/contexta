//! prompt 注入契约测试：NEWS+来源 → user prompt 含来源块；无来源 → 不含；标题清单注入；
//! 占位符永不残留。
use async_trait::async_trait;
use chrono::Local;
use server::config::Config;
use server::db;
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::services::llm_service;
use server::services::source_service::SourceArticle;
use sqlx::SqlitePool;
use std::sync::atomic::{AtomicUsize, Ordering};

static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-fact-prompt-{}-{}.db", std::process::id(), n)
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
        chinadaily_base_url: "https://www.chinadaily.com.cn".into(),
        source_max_age_days: 3,
        source_fetch_timeout_secs: 15,
        recent_title_days: 14,
    }
}

async fn cleanup(pool: SqlitePool, db_path: &str) {
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

async fn setup() -> (SqlitePool, Config, String) {
    let db_path = unique_db_path();
    let cfg = test_cfg(&db_path);
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    (pool, cfg, db_path)
}

/// 捕获 user prompt 并返回固定合法文章 XML（不嵌 prompt，避免换行破坏 parse_article）。
struct CapturingApi {
    prompts: std::sync::Mutex<Vec<String>>,
}
#[async_trait]
impl DeepSeekApi for CapturingApi {
    async fn chat(&self, _s: &str, u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        self.prompts.lock().unwrap().push(u.to_string());
        Ok(DeepSeekResponse {
            content: "<title>T</title><paragraph>P1.</paragraph><translation>译1。</translation>"
                .into(),
            prompt_tokens: 1,
            completion_tokens: 1,
        })
    }
}

fn api() -> CapturingApi {
    CapturingApi {
        prompts: std::sync::Mutex::new(Vec::new()),
    }
}

fn source() -> SourceArticle {
    SourceArticle {
        id: 7,
        url: "https://cd.example/7".into(),
        title: "Real Event Title".into(),
        body: "Real facts body with numbers such as 42 percent growth.".into(),
        published_at: "2026-08-17".into(),
    }
}

#[tokio::test]
async fn news_with_source_injects_facts_block() {
    let (pool, cfg, db_path) = setup().await;
    let a = api();
    llm_service::generate_article_content(&pool, &a, &cfg, "MEDIUM", "NEWS", 1, Some(&source()))
        .await
        .unwrap();
    let u = a.prompts.lock().unwrap()[0].clone();
    assert!(u.contains("Facts source (China Daily, 2026-08-17):"), "来源块应含日期: {u}");
    assert!(u.contains("Real Event Title"), "来源标题应注入");
    assert!(u.contains("Real facts body"), "来源正文应注入");
    assert!(u.contains("Do not add facts not present in the source"), "重写指令应注入");
    assert!(!u.contains("{{sourceArticle}}"), "占位符必须被替换");
    assert!(!u.contains("{{recentTitles}}"), "占位符必须被替换");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn without_source_no_facts_block() {
    let (pool, cfg, db_path) = setup().await;
    let a = api();
    llm_service::generate_article_content(&pool, &a, &cfg, "LOW", "DAILY_CONVERSATION", 1, None)
        .await
        .unwrap();
    let u = a.prompts.lock().unwrap()[0].clone();
    assert!(!u.contains("Facts source"), "无来源时不得注入来源块: {u}");
    assert!(!u.contains("Real Event Title"), "无来源时不得注入来源内容");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn recent_titles_injected_and_empty_when_none() {
    let (pool, cfg, db_path) = setup().await;
    // 无已生成文章 → 不含防重指令
    let a = api();
    llm_service::generate_article_content(&pool, &a, &cfg, "LOW", "SCENE_DESCRIPTION", 1, None)
        .await
        .unwrap();
    let u = a.prompts.lock().unwrap()[0].clone();
    assert!(!u.contains("recently published"), "无标题时不得注入防重清单: {u}");
    // 种子 2 篇已生成文章 → 标题清单注入（近 14 天窗口）
    let today = Local::now().format("%Y-%m-%d").to_string();
    let now_ms = chrono::Utc::now().timestamp_millis();
    for (i, t) in ["Weather Report A", "Economy News B"].iter().enumerate() {
        sqlx::query(
            "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, created_at, updated_at)
             VALUES (?, 'MEDIUM', 'NEWS', ?, ?, 'approved', ?, ?)",
        )
        .bind(&today)
        .bind(i as i64)
        .bind(t)
        .bind(now_ms)
        .bind(now_ms)
        .execute(&pool)
        .await
        .unwrap();
    }
    let a = api();
    llm_service::generate_article_content(&pool, &a, &cfg, "LOW", "SIMPLE_STORY", 2, None)
        .await
        .unwrap();
    let u = a.prompts.lock().unwrap()[0].clone();
    assert!(u.contains("recently published"), "应注入防重指令: {u}");
    assert!(u.contains("- Weather Report A"), "标题 1 应在清单中");
    assert!(u.contains("- Economy News B"), "标题 2 应在清单中");
    cleanup(pool, &db_path).await;
}
