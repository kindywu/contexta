// Task 8：文章生成/审核状态机集成测试。mock LLM 返回合法文章 XML（parse_article 可解析），
// 直接调用 service 函数（不走路由）验证幂等生成 / 审核 / 补生成上限 / 每日预算 / 可见性。
// 隔离模式与 llm_test 一致：唯一库路径 + 收尾 close + 清理三件套。

use async_trait::async_trait;
use chrono::Utc;
use server::config::Config;
use server::db;
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::response::AppError;
use server::services::article_service;
use sqlx::SqlitePool;
use std::sync::atomic::{AtomicUsize, Ordering};

static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-article-{}-{}.db", std::process::id(), n)
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

// mock DeepSeek：user prompt 含分类名（如 "NEWS"）与生成指南；
// 返回含分类名的合法文章 XML（<title>/<paragraph>/<translation> 齐备，parse_article 可解析）。
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
async fn ensure_generation_creates_15_articles_idempotent() {
    let (pool, cfg, db_path) = setup().await;
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, "2026-08-14")
        .await
        .unwrap();
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total, 15, "每难度 5 篇共 15 篇");
    let per: Vec<(String, i64)> =
        sqlx::query_as("SELECT difficulty, COUNT(*) FROM article GROUP BY difficulty")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(per.len(), 3, "三个难度各应有文章");
    for (d, n) in &per {
        assert_eq!(*n, 5, "difficulty {d} 应有 5 篇");
    }
    let not_pending: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM article WHERE status != 'pending_review'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(not_pending, 0, "全部应为 pending_review");
    // 幂等：再跑一次不新增
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, "2026-08-14")
        .await
        .unwrap();
    let total2: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total2, 15, "第二次调用必须幂等，不得新增");
    // 段落存储格式契约：单列 `英文|||中文`（下发时拆分，T10 消费）
    let para: String = sqlx::query_scalar("SELECT text FROM article_paragraph LIMIT 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(para, "P1.|||译1。");
    // token 真值落库（审查修复：成本换算）——mock 固定返回 1/1
    let (pt, ct): (i64, i64) =
        sqlx::query_as("SELECT prompt_tokens, completion_tokens FROM article ORDER BY id LIMIT 1")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(pt, 1, "prompt_tokens 应记真值");
    assert_eq!(ct, 1, "completion_tokens 应记真值");
    // usage_log 记 article_generate（真值 token）
    let usage: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM usage_log WHERE endpoint = 'article_generate'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(usage, 15, "每篇生成各记一条用量");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn concurrent_ensure_generation_is_idempotent() {
    let (pool, cfg, db_path) = setup().await;
    // BEGIN IMMEDIATE 序列化：两次并发 ensure 仍只生成 15 篇（每难度 5）
    let (r1, r2) = tokio::join!(
        article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, "2026-08-15"),
        article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, "2026-08-15"),
    );
    assert!(r1.is_ok(), "并发调用 1 失败: {:?}", r1.err());
    assert!(r2.is_ok(), "并发调用 2 失败: {:?}", r2.err());
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        total, 15,
        "并发 ensure 必须幂等（后到者等待先到者提交后计数）"
    );
    let per: Vec<(String, i64)> =
        sqlx::query_as("SELECT difficulty, COUNT(*) FROM article GROUP BY difficulty")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(per.len(), 3);
    for (d, n) in &per {
        assert_eq!(*n, 5, "difficulty {d} 并发后仍应 5 篇");
    }
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn reject_regenerates_until_cap_then_final() {
    let (pool, cfg, db_path) = setup().await;
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, "2026-08-14")
        .await
        .unwrap();
    let first: i64 = sqlx::query_scalar("SELECT id FROM article ORDER BY id LIMIT 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    // 第一次 reject：旧行 → rejected，新行 pending_review（regenerate_count=1）
    article_service::reject_article(&pool, &cfg, &MockArticleApi, first, "low quality")
        .await
        .unwrap();
    let old_status: String = sqlx::query_scalar("SELECT status FROM article WHERE id = ?")
        .bind(first)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(old_status, "rejected");
    let mut cur: i64 = sqlx::query_scalar("SELECT MAX(id) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(cur > first, "补生成应产生新行");
    let (st, regen): (String, i64) =
        sqlx::query_as("SELECT status, regenerate_count FROM article WHERE id = ?")
            .bind(cur)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(st, "pending_review");
    assert_eq!(regen, 1);
    // 连续 reject：第 2、3 次各产生新行（regenerate_count=2、3），第 4 次 → rejected_final 且不再新增
    for k in 2..=4 {
        article_service::reject_article(&pool, &cfg, &MockArticleApi, cur, "bad")
            .await
            .unwrap();
        let st: String = sqlx::query_scalar("SELECT status FROM article WHERE id = ?")
            .bind(cur)
            .fetch_one(&pool)
            .await
            .unwrap();
        if k == 4 {
            assert_eq!(
                st, "rejected_final",
                "第 4 次 reject 后该分支终态，不再补生成"
            );
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
            assert_eq!(regen2, k as i64);
            cur = m;
        }
    }
    let m: i64 = sqlx::query_scalar("SELECT MAX(id) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(m, cur, "第 4 次 reject 后不得新增行");
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(total, 18, "15 篇 + 3 次成功补生成（第 4 次不新增）");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn budget_blocks_generation() {
    let (pool, mut cfg, db_path) = setup().await;
    cfg.article_budget_daily = 10;
    // 先造 10 行（created_at 今日，计入预算）
    let now = Utc::now().timestamp_millis();
    for i in 0..10 {
        sqlx::query(
            "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, created_at, updated_at)
             VALUES ('2026-08-14', 'LOW', 'DAILY_CONVERSATION', ?, 't', 'pending_review', ?, ?)",
        )
        .bind(i)
        .bind(now)
        .bind(now)
        .execute(&pool)
        .await
        .unwrap();
    }
    let r = article_service::generate_one(
        &pool,
        &cfg,
        &MockArticleApi,
        "2026-08-14",
        "LOW",
        "DAILY_CONVERSATION",
        99,
    )
    .await;
    assert!(
        matches!(r, Err(AppError::QuotaExceeded(_))),
        "预算耗尽必须 QuotaExceeded: {:?}",
        r.err()
    );
    let n: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(n, 10, "超预算不得写入新行");
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn approved_articles_visible_others_not() {
    let (pool, cfg, db_path) = setup().await;
    article_service::ensure_daily_generation(&pool, &cfg, &MockArticleApi, "2026-08-14")
        .await
        .unwrap();
    // 未审：下发列表为空
    assert!(
        article_service::get_approved_by_date(&pool, "2026-08-14")
            .await
            .unwrap()
            .is_empty()
    );
    let id: i64 = sqlx::query_scalar("SELECT id FROM article ORDER BY id LIMIT 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    article_service::approve_article(&pool, id).await.unwrap();
    // approved 可见：仅这一篇
    let list = article_service::get_approved_by_date(&pool, "2026-08-14")
        .await
        .unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, id);
    assert_eq!(list[0].status, "approved");
    assert_eq!(list[0].paragraphs.len(), 1);
    assert_eq!(list[0].paragraphs[0].1, "P1.");
    assert_eq!(list[0].paragraphs[0].2, "译1。");
    // 其余 14 篇 pending 不可见
    assert_eq!(
        article_service::get_approved_by_date(&pool, "2026-08-14")
            .await
            .unwrap()
            .len(),
        1
    );
    // 其他日期不可见
    assert!(
        article_service::get_approved_by_date(&pool, "2026-08-13")
            .await
            .unwrap()
            .is_empty()
    );
    // get_article 单篇详情
    let v = article_service::get_article(&pool, id).await.unwrap();
    assert_eq!(v.target_date, "2026-08-14");
    assert_eq!(v.difficulty, "LOW");
    // 已 approved 不可重复审核
    let r = article_service::approve_article(&pool, id).await;
    assert!(
        matches!(r, Err(AppError::NotFound(_))),
        "重复 approve 必须 NotFound"
    );
    // list_articles 动态过滤（date/status 白名单列 + 全绑参）
    let all = article_service::list_articles(&pool, Some("2026-08-14"), None)
        .await
        .unwrap();
    assert_eq!(all.len(), 15);
    let approved = article_service::list_articles(&pool, None, Some("approved"))
        .await
        .unwrap();
    assert_eq!(approved.len(), 1);
    assert_eq!(approved[0].id, id);
    let both = article_service::list_articles(&pool, Some("2026-08-14"), Some("approved"))
        .await
        .unwrap();
    assert_eq!(both.len(), 1);
    let none = article_service::list_articles(&pool, None, None)
        .await
        .unwrap();
    assert_eq!(none.len(), 15, "无过滤返回全部");
    cleanup(pool, &db_path).await;
}
