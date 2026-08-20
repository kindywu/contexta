//! 事实源服务集成测试：选源预占（不重复）、池空抓取补充、抓取失败降级、新鲜度过滤。
use async_trait::async_trait;
use chrono::{Duration, Local, Utc};
use server::config::Config;
use server::db;
use server::drivers::chinadaily::{FetchedSource, SourceFetcher};
use server::services::source_service;
use sqlx::SqlitePool;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-src-svc-{}-{}.db", std::process::id(), n)
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

/// mock 抓取器：返回预设来源 / 固定失败；fetch 调用次数可断言（Arc 计数器）。
struct MockFetcher {
    sources: Vec<FetchedSource>,
    fail: bool,
    calls: Arc<AtomicUsize>,
}
#[async_trait]
impl SourceFetcher for MockFetcher {
    async fn fetch_recent(&self, _cfg: &Config) -> Result<Vec<FetchedSource>, anyhow::Error> {
        self.calls.fetch_add(1, Ordering::SeqCst);
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
async fn pick_reserves_sources_in_freshness_order_never_repeats() {
    let (pool, cfg, db_path) = setup().await;
    let now = Utc::now().timestamp_millis();
    for (i, url) in ["https://cd/1", "https://cd/2", "https://cd/3"].iter().enumerate() {
        let date = (Local::now() - Duration::days(i as i64)).format("%Y-%m-%d").to_string();
        sqlx::query(
            "INSERT INTO article_source (source_url, title, body, published_at, is_used, created_at, updated_at)
             VALUES (?, ?, 'b', ?, 0, ?, ?)",
        )
        .bind(url)
        .bind(url)
        .bind(&date)
        .bind(now)
        .bind(now)
        .execute(&pool)
        .await
        .unwrap();
    }
    let fetcher = MockFetcher { sources: vec![], fail: false, calls: Arc::new(AtomicUsize::new(0)) };
    // 按最新优先：days_ago=0 → 1 → 2
    for expected in ["https://cd/1", "https://cd/2", "https://cd/3"] {
        let s = source_service::pick_source(&pool, &cfg, &fetcher)
            .await
            .unwrap()
            .expect("池内应有未用来源");
        assert_eq!(s.url, expected, "应按 published_at 降序选中");
        assert_eq!(s.title, expected);
    }
    // 池空 → 触发抓取（mock 返回空 → 存 0 行）→ 再选仍 None
    assert!(source_service::pick_source(&pool, &cfg, &fetcher).await.unwrap().is_none());
    let used: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article_source WHERE is_used = 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(used, 3, "三篇全部预占");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn pick_fetches_when_pool_empty_and_stores_all() {
    let (pool, cfg, db_path) = setup().await;
    let calls = Arc::new(AtomicUsize::new(0));
    let fetcher = MockFetcher {
        sources: vec![fetched("https://cd/a", 0), fetched("https://cd/b", 1)],
        fail: false,
        calls: calls.clone(),
    };
    let s1 = source_service::pick_source(&pool, &cfg, &fetcher).await.unwrap().unwrap();
    assert_eq!(s1.url, "https://cd/a");
    let s2 = source_service::pick_source(&pool, &cfg, &fetcher).await.unwrap().unwrap();
    assert_eq!(s2.url, "https://cd/b");
    assert_eq!(calls.load(Ordering::SeqCst), 1, "池未空时不得重复抓取");
    let stored: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article_source")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stored, 2, "抓取产物全部入库");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn pick_degrades_to_none_when_fetch_fails() {
    let (pool, cfg, db_path) = setup().await;
    let fetcher = MockFetcher { sources: vec![], fail: true, calls: Arc::new(AtomicUsize::new(0)) };
    let r = source_service::pick_source(&pool, &cfg, &fetcher).await.unwrap();
    assert!(r.is_none(), "抓取失败必须降级 Ok(None)，不得上抛");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn stale_sources_are_not_picked() {
    let (pool, cfg, db_path) = setup().await;
    let now = Utc::now().timestamp_millis();
    // 4 天前（max_age=3 之外）与 1 天前（窗口内）
    for (url, days_ago) in [("https://cd/stale", 4i64), ("https://cd/fresh", 1i64)] {
        let date = (Local::now() - Duration::days(days_ago)).format("%Y-%m-%d").to_string();
        sqlx::query(
            "INSERT INTO article_source (source_url, title, body, published_at, is_used, created_at, updated_at)
             VALUES (?, ?, 'b', ?, 0, ?, ?)",
        )
        .bind(url)
        .bind(url)
        .bind(&date)
        .bind(now)
        .bind(now)
        .execute(&pool)
        .await
        .unwrap();
    }
    let fetcher = MockFetcher { sources: vec![], fail: false, calls: Arc::new(AtomicUsize::new(0)) };
    let s = source_service::pick_source(&pool, &cfg, &fetcher).await.unwrap().unwrap();
    assert_eq!(s.url, "https://cd/fresh", "过期来源（4 天前）不得入选");
    cleanup(pool, &db_path).await;
}

/// 挂起不返回的抓取器（模拟黑洞上游）。`started` 在 fetch_recent 被调用时 notify——
/// 此刻 pick_source 已越过 try_pick（空池 SELECT 完成、无进行中 DB 往返），
/// 测试收到通知后再推进虚拟时钟：超时定时器已武装，推进不会误伤真实 IO。
struct HangingFetcher {
    started: Arc<tokio::sync::Notify>,
}
#[async_trait]
impl SourceFetcher for HangingFetcher {
    async fn fetch_recent(&self, _cfg: &Config) -> Result<Vec<FetchedSource>, anyhow::Error> {
        self.started.notify_one();
        tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
        Ok(Vec::new())
    }
}

#[tokio::test]
async fn pick_source_times_out_hanging_fetch() {
    let (pool, cfg, db_path) = setup().await;
    // 不用 start_paused：setup 的 sqlx 建池在暂停时钟下会失败——暂停后运行时 park 时
    // auto-advance 跳到 sqlx 池 acquire 的 30s 超时定时器（虚拟时钟跳跃先于真实 IO 完成）
    // → PoolTimedOut（与 task_test 同款坑）。暂停后 DB 往返仍是真实时间，但同样的
    // auto-advance 会在任务侧查询期间误触 acquire 定时器，因此用保活 blocking 任务
    // 抑制 auto-advance（tokio 文档「Preventing auto-advance」：blocking 任务运行期间
    // 时钟不自动推进），真实 IO 得以在冻结时钟下完成；其退出（halt）后 auto-advance 恢复。
    tokio::time::pause();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let (halt_tx, halt_rx) = std::sync::mpsc::channel();
    let _keepalive = tokio::task::spawn_blocking(move || {
        let _ = ready_tx.send(());
        // 10s 上限：测试异常路径（panic 前未 halt）也不挂死，最多拖慢收尾
        let _ = halt_rx.recv_timeout(std::time::Duration::from_secs(10));
    });
    ready_rx.recv().unwrap(); // 等阻塞线程真正启动（auto-advance 抑制已生效）
    let notify = Arc::new(tokio::sync::Notify::new());
    let fetcher = HangingFetcher { started: notify.clone() };
    let started = notify.notified();
    let pool2 = pool.clone();
    let cfg2 = cfg.clone();
    let mut task = tokio::spawn(async move {
        source_service::pick_source(&pool2, &cfg2, &fetcher).await
    });
    // 等 fetch_recent 被调用：try_pick 的 SELECT 已完成、60s 超时定时器已武装。
    // 与任务完成竞速：若任务提前结束（回归：未走到抓取），走 task 分支判失败而非挂死。
    tokio::select! {
        _ = started => {}
        _ = &mut task => {}
    }
    let _ = halt_tx.send(()); // 释放保活 → auto-advance 恢复
    // 虚拟时钟推进越过总超时 → 超时触发 → 按抓取失败降级
    tokio::time::advance(std::time::Duration::from_secs(
        source_service::FETCH_TOTAL_TIMEOUT_SECS + 1,
    ))
    .await;
    let r = task.await.unwrap().unwrap();
    assert!(r.is_none(), "挂起抓取超时应降级 Ok(None)");
    tokio::time::resume();
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn store_sources_is_idempotent_on_duplicate_urls() {
    let (pool, _cfg, db_path) = setup().await;
    let batch = vec![fetched("https://cd/dup", 0), fetched("https://cd/dup", 1)];
    let n = source_service::store_sources(&pool, batch).await.unwrap();
    assert_eq!(n, 1, "同批重复 URL 只插入 1 行");
    let rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article_source")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rows, 1);
    cleanup(pool, &db_path).await;
}
