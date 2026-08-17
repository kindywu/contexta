//! 管线级事实锚定集成测试：NEWS 生成选源占用、非 NEWS 不占用、来源可查、reject 不重复耗源、
//! 抓取失败降级自由发挥。
use async_trait::async_trait;
use chrono::{Duration, Local, Utc};
use server::config::Config;
use server::db;
use server::drivers::chinadaily::{FetchedSource, NoopFetcher, SourceFetcher};
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::services::article_service;
use sqlx::SqlitePool;
use std::sync::atomic::{AtomicUsize, Ordering};

static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-fact-article-{}-{}.db", std::process::id(), n)
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

/// 固定合法文章 XML（不嵌 user prompt，避免换行破坏 parse_article）。
struct MockArticleApi;
#[async_trait]
impl DeepSeekApi for MockArticleApi {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        Ok(DeepSeekResponse {
            content: "<title>T</title><paragraph>P1.</paragraph><translation>译1。</translation>"
                .into(),
            prompt_tokens: 1,
            completion_tokens: 1,
        })
    }
}

struct MockFetcher {
    sources: Vec<FetchedSource>,
    fail: bool,
}
#[async_trait]
impl SourceFetcher for MockFetcher {
    async fn fetch_recent(&self, _cfg: &Config) -> Result<Vec<FetchedSource>, anyhow::Error> {
        if self.fail {
            Err(anyhow::anyhow!("mock fetch failure"))
        } else {
            Ok(self.sources.clone())
        }
    }
}

fn fetched(url: &str, days_ago: i64) -> FetchedSource {
    FetchedSource {
        url: url.to_string(),
        title: format!("T-{url}"),
        body: format!("Body of {url}"),
        published_at: (Local::now() - Duration::days(days_ago)).format("%Y-%m-%d").to_string(),
    }
}

#[tokio::test]
async fn news_consumes_sources_others_not_and_url_visible() {
    let (pool, cfg, db_path) = setup().await;
    let fetcher = MockFetcher {
        sources: vec![fetched("https://cd/1", 0), fetched("https://cd/2", 1), fetched("https://cd/3", 2)],
        fail: false,
    };
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, &fetcher, "2026-08-14")
        .await
        .unwrap();
    // 该日 NEWS 文章数 == 已占用来源数（每篇 NEWS 恰好一篇来源）
    let news: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM article WHERE target_date = '2026-08-14' AND content_category = 'NEWS'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(news >= 1, "MEDIUM 5 篇中应至少 1 篇 NEWS");
    let used: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article_source WHERE is_used = 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(used, news, "每篇 NEWS 恰好占用一篇来源");
    // NEWS 行有 source_article_id；非 NEWS 行全部 NULL
    let news_with_src: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM article WHERE content_category = 'NEWS' AND source_article_id IS NOT NULL",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(news_with_src, news);
    let non_news_with_src: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM article WHERE content_category != 'NEWS' AND source_article_id IS NOT NULL",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(non_news_with_src, 0, "非 NEWS 不得引用来源");
    // 来源可见：get_article 返回 source_url
    let news_id: i64 = sqlx::query_scalar(
        "SELECT id FROM article WHERE content_category = 'NEWS' AND source_article_id IS NOT NULL ORDER BY id LIMIT 1",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    let v = article_service::get_article(&pool, news_id).await.unwrap();
    assert_eq!(v.source_url.as_deref(), Some("https://cd/1"), "NEWS 详情应含来源链接");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn reject_replacement_does_not_reuse_source() {
    let (pool, cfg, db_path) = setup().await;
    let fetcher = MockFetcher {
        sources: vec![fetched("https://cd/1", 0), fetched("https://cd/2", 1)],
        fail: false,
    };
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, &fetcher, "2026-08-15")
        .await
        .unwrap();
    let used_before: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM article_source WHERE is_used = 1")
            .fetch_one(&pool)
            .await
            .unwrap();
    let news_id: i64 = sqlx::query_scalar(
        "SELECT id FROM article WHERE content_category = 'NEWS' AND source_article_id IS NOT NULL ORDER BY id LIMIT 1",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    // reject：补生成分类轮换（order+regen+1 取模），补生行必非 NEWS → 不新耗来源
    article_service::reject_article(&pool, &cfg, &MockArticleApi, &fetcher, news_id, "bad")
        .await
        .unwrap();
    let used_after: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM article_source WHERE is_used = 1")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(used_after, used_before, "reject 补生成不得重复耗源（补生行非 NEWS）");
    let replacement: i64 = sqlx::query_scalar("SELECT MAX(id) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    let (cat, src): (String, Option<i64>) =
        sqlx::query_as("SELECT content_category, source_article_id FROM article WHERE id = ?")
            .bind(replacement)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_ne!(cat, "NEWS", "补生行分类已轮换，非 NEWS");
    assert!(src.is_none(), "非 NEWS 补生行无来源");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn fetch_failure_degrades_to_free_write() {
    let (pool, cfg, db_path) = setup().await;
    // 直接构造 NEWS 预占行 + 抓取失败 fetcher → generate_one 仍成功（自由发挥降级）
    let now = Utc::now().timestamp_millis();
    let id = sqlx::query(
        "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, regenerate_count, created_at, updated_at)
         VALUES ('2026-08-17', 'MEDIUM', 'NEWS', 1, NULL, 'pending_review', 0, ?, ?)",
    )
    .bind(now)
    .bind(now)
    .execute(&pool)
    .await
    .unwrap()
    .last_insert_rowid();
    let fetcher = MockFetcher { sources: vec![], fail: true };
    article_service::generate_one(&pool, &cfg, &MockArticleApi, &fetcher, id)
        .await
        .unwrap();
    let st: String = sqlx::query_scalar("SELECT status FROM article WHERE id = ?")
        .bind(id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(st, "pending_review", "降级生成成功，行仍可过审");
    let src: Option<i64> = sqlx::query_scalar("SELECT source_article_id FROM article WHERE id = ?")
        .bind(id)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(src.is_none(), "无来源时 source_article_id 为 NULL");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn noop_fetcher_keeps_articles_working() {
    let (pool, cfg, db_path) = setup().await;
    // 无任何来源 + NoopFetcher → 15 篇全部正常生成（现有行为不回归）
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, &NoopFetcher, "2026-08-18")
        .await
        .unwrap();
    let total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM article WHERE status = 'pending_review' AND title IS NOT NULL",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(total, 15);
    cleanup(pool, &db_path).await;
}
