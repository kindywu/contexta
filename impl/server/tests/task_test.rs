// Task 9：每日生成任务集成测试。
// 测试 1（run_startup_fill）：启动补漏生成今天+明天各 15 篇，重复调用幂等。
// 测试 2（daily_generation_loop）：tokio 暂停时钟 + 逐小时 advance 推进到配置时刻，
// 断言定时器触发 ensure 且 target_date = 明天（不依赖真实等待）。
// 隔离模式与 article_service_test 一致：唯一库路径 + 收尾 close + 清理三件套。

use async_trait::async_trait;
use chrono::{Local, NaiveDate};
use server::AppState;
use server::config::Config;
use server::db;
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::tasks::article_daily_task::{daily_generation_loop, run_startup_fill};
use server::tasks::default_sleep;
use sqlx::SqlitePool;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-task-{}-{}.db", std::process::id(), n)
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

// mock DeepSeek（同 T8）：user prompt 含分类名；返回含分类名的合法文章 XML，parse_article 可解析。
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
async fn startup_fill_generates_today_and_tomorrow() {
    let (pool, cfg, db_path) = setup().await;
    let state = AppState {
        pool: pool.clone(),
        cfg: Arc::new(cfg.clone()),
    };
    // 首跑：今天 15 行 + 明天 15 行
    run_startup_fill(&state, &cfg, &MockArticleApi)
        .await
        .unwrap();
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total, 30, "启动补漏应生成今天+明天共 30 篇");
    let per: Vec<(String, i64)> =
        sqlx::query_as("SELECT target_date, COUNT(*) FROM article GROUP BY target_date")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(per.len(), 2, "恰好两个日期（今天、明天）");
    for (d, n) in &per {
        assert_eq!(*n, 15, "日期 {d} 应有 15 篇");
    }
    // 两个日期必须相邻（今天/明天语义，不依赖具体日期字面量，跨午夜安全）
    let mut dates: Vec<NaiveDate> = per
        .iter()
        .map(|(d, _)| NaiveDate::parse_from_str(d, "%Y-%m-%d").unwrap())
        .collect();
    dates.sort();
    let diff = dates[1] - dates[0];
    assert_eq!(diff.num_days(), 1, "今天与明天必须相邻");
    // 幂等：再跑一次行数不变
    run_startup_fill(&state, &cfg, &MockArticleApi)
        .await
        .unwrap();
    let total2: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total2, 30, "重复启动补漏必须幂等，不得新增");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn timer_fires_at_configured_hour() {
    let (pool, cfg, db_path) = setup().await;
    let state = AppState {
        pool: pool.clone(),
        cfg: Arc::new(cfg.clone()),
    };
    let today = Local::now().format("%Y-%m-%d").to_string();
    // 暂停 tokio 虚拟时钟：任务里 sleep 挂起在虚拟时刻，测试逐小时 advance 推进，
    // 到配置时刻（daily_generate_hour=3）定时器触发 → ensure(target_date=明天)。
    tokio::time::pause();
    let handle = tokio::spawn(daily_generation_loop(
        state,
        Arc::new(cfg.clone()),
        &MockArticleApi,
        default_sleep(),
    ));
    // 最长等待约 24h（now.hour() >= 配置时刻时等到明天该时刻），30h 上限足够；
    // 每次 advance 后多次 yield 让任务跑完 ensure（15 篇 mock 填充 + 落库）
    for _ in 0..30 {
        tokio::time::advance(std::time::Duration::from_secs(3600)).await;
        for _ in 0..20 {
            tokio::task::yield_now().await;
        }
        let n: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
            .fetch_one(&pool)
            .await
            .unwrap();
        if n >= 15 {
            break;
        }
    }
    handle.abort();
    let _ = handle.await;
    // 库初始为空且循环不做启动补漏：这 15 行只可能来自定时器到点触发的 ensure
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total, 15, "定时触发应生成 15 篇");
    let dates: Vec<(String, i64)> =
        sqlx::query_as("SELECT target_date, COUNT(*) FROM article GROUP BY target_date")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(dates.len(), 1, "只生成一个日期（明天）");
    assert_eq!(dates[0].1, 15);
    assert_ne!(
        dates[0].0, today,
        "不能生成今天——断言 target_date = 明天（非真实等待，虚拟时钟推进）"
    );
    cleanup(pool, &db_path).await;
}
