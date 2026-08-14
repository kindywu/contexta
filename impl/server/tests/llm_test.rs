use chrono::Utc;
use server::config::Config;
use server::db;
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::response::AppError;
use server::services::llm_service;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};

// T7：查词服务集成测试。mock 状态注入：llm_service::word_lookup 接受 &dyn DeepSeekApi——
// 集成测试直接调用 service 函数（不走路由）验证缓存/配额，路由测试只验认证与 JSON 形状。

/// 与 auth_test 一致的隔离模式：唯一库路径 + 收尾 close + 清理三件套。
static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-llm-{}-{}.db", std::process::id(), n)
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

async fn cleanup(pool: sqlx::SqlitePool, db_path: &str) {
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

async fn setup() -> (sqlx::SqlitePool, Config, String) {
    let db_path = unique_db_path();
    let cfg = test_cfg(&db_path);
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    (pool, cfg, db_path)
}

struct MockDeepSeek {
    calls: Arc<AtomicUsize>,
    content: String,
    /// 最近一次 LLM 调用的 system/user（Task 2 DB 化断言：验证 LLM 收到 DB 修改后的内容）。
    captured_system: Arc<Mutex<Option<String>>>,
    captured_user: Arc<Mutex<Option<String>>>,
}

impl MockDeepSeek {
    fn new(content: &str) -> Self {
        Self {
            calls: Arc::new(AtomicUsize::new(0)),
            content: content.to_string(),
            captured_system: Arc::new(Mutex::new(None)),
            captured_user: Arc::new(Mutex::new(None)),
        }
    }
}

#[async_trait::async_trait]
impl DeepSeekApi for MockDeepSeek {
    async fn chat(&self, s: &str, u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        *self.captured_system.lock().unwrap() = Some(s.to_string());
        *self.captured_user.lock().unwrap() = Some(u.to_string());
        Ok(DeepSeekResponse {
            content: self.content.clone(),
            prompt_tokens: 5,
            completion_tokens: 10,
        })
    }
}

/// 合法查词 XML（parse_word_lookup 可解析：spelling/phonetic/1 sense/1 example）。
const VALID_XML: &str = "<spelling>ocean</spelling><phonetic>/ˈoʊʃən/</phonetic>\
<sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>海洋</chineseMeaning>\
<englishDefinition>a very large expanse of sea</englishDefinition>\
<example><en>The ocean is deep and wide.</en><zh>海洋又深又宽。</zh></example></sense>";

/// 合法但 spelling 与请求词（"running"）不一致的 XML（LLM 输出屈折归一形态）。
const RUN_XML: &str = "<spelling>run</spelling><phonetic>/rʌn/</phonetic>\
<sense><partOfSpeech>v.</partOfSpeech><chineseMeaning>跑</chineseMeaning>\
<englishDefinition>to move quickly on foot</englishDefinition>\
<example><en>She runs every morning.</en><zh>她每天早上跑步。</zh></example></sense>";

/// 统计 word_lookup 用量行数。
async fn usage_rows(pool: &sqlx::SqlitePool) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM usage_log WHERE endpoint = 'word_lookup'")
        .fetch_one(pool)
        .await
        .unwrap()
}

#[tokio::test]
async fn first_call_hits_llm_second_call_cached() {
    let (pool, cfg, db_path) = setup().await;
    let mock = MockDeepSeek::new(VALID_XML);
    let w1 = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    assert!(w1.is_ok(), "first call should hit LLM: {:?}", w1.err());
    assert_eq!(w1.unwrap().spelling, "ocean");
    assert_eq!(mock.calls.load(Ordering::SeqCst), 1);
    let w2 = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    assert!(w2.is_ok(), "second call should hit cache: {:?}", w2.err());
    assert_eq!(
        mock.calls.load(Ordering::SeqCst),
        1,
        "second call must be served from cache"
    );
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn cache_hit_does_not_consume_quota() {
    let (pool, mut cfg, db_path) = setup().await;
    cfg.word_quota_daily = 2;
    let mock = MockDeepSeek::new(VALID_XML);
    for _ in 0..5 {
        let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
        assert!(
            r.is_ok(),
            "cached repeats must not consume quota: {:?}",
            r.err()
        );
    }
    assert_eq!(
        mock.calls.load(Ordering::SeqCst),
        1,
        "LLM must be called exactly once"
    );
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn quota_exceeded_rejected() {
    let (pool, mut cfg, db_path) = setup().await;
    cfg.word_quota_daily = 2;
    let mock = MockDeepSeek::new(VALID_XML);
    for word in ["alpha", "beta"] {
        let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", word).await;
        assert!(r.is_ok(), "{word} should be within quota: {:?}", r.err());
    }
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "gamma").await;
    assert!(
        matches!(r, Err(AppError::QuotaExceeded(_))),
        "3rd distinct word must exceed daily quota"
    );
    cleanup(pool, &db_path).await;
}

#[tokio::test]
async fn parse_failure_returns_pipeline_blocking() {
    let (pool, cfg, db_path) = setup().await;
    let mock = MockDeepSeek::new("not xml at all");
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    assert!(
        matches!(r, Err(AppError::PipelineBlocking(_))),
        "unparseable LLM output must be PipelineBlocking"
    );
    cleanup(pool, &db_path).await;
}

/// I1：LLM 调用成功但解析失败时也必须记账——解析失败路径同样消耗配额，
/// 否则恶意用户可无限用易触发解析失败的词绕过配额烧钱。
#[tokio::test]
async fn parse_failure_still_records_usage() {
    let (pool, cfg, db_path) = setup().await;
    let mock = MockDeepSeek::new("not xml at all");
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    assert!(matches!(r, Err(AppError::PipelineBlocking(_))));
    assert_eq!(
        usage_rows(&pool).await,
        1,
        "parse failure must still record usage (real LLM call spent money)"
    );
    // 配额口径统一：失败解析同样占用配额，第二次（不同词）不应被重复放行
    let r2 = llm_service::word_lookup(&pool, &cfg, &mock, "138", "river").await;
    assert!(matches!(r2, Err(AppError::PipelineBlocking(_))));
    assert_eq!(usage_rows(&pool).await, 2);
    cleanup(pool, &db_path).await;
}

/// I2a：缓存写入失败必须降级——查词结果仍返回（不 500），用量照记。
#[tokio::test]
async fn cache_write_failure_still_returns_result() {
    let (pool, cfg, db_path) = setup().await;
    // SQLite 触发器注入写失败：INSERT 到 word_lookup_cache 一律 ABORT
    sqlx::query(
        "CREATE TRIGGER fail_cache_insert BEFORE INSERT ON word_lookup_cache \
         BEGIN SELECT RAISE(ABORT, 'injected cache write failure'); END",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mock = MockDeepSeek::new(VALID_XML);
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    let w = r.expect("cache write failure must degrade, not fail the lookup");
    assert_eq!(w.spelling, "ocean");
    assert_eq!(
        usage_rows(&pool).await,
        1,
        "usage must still be recorded when cache write fails"
    );
    cleanup(pool, &db_path).await;
}

/// I2b：用量写入失败必须降级——查词结果仍返回（不 500）。
#[tokio::test]
async fn usage_write_failure_still_returns_result() {
    let (pool, cfg, db_path) = setup().await;
    // SQLite 触发器注入写失败：INSERT 到 usage_log 一律 ABORT
    sqlx::query(
        "CREATE TRIGGER fail_usage_insert BEFORE INSERT ON usage_log \
         BEGIN SELECT RAISE(ABORT, 'injected usage write failure'); END",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mock = MockDeepSeek::new(VALID_XML);
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    let w = r.expect("usage write failure must degrade, not fail the lookup");
    assert_eq!(w.spelling, "ocean");
    cleanup(pool, &db_path).await;
}

/// I3：LLM 返回的 spelling 与请求词不一致（变体/屈折归一）时不得写入共享缓存——
/// 否则全用户 30 天都会查到错误词条；结果仍返回请求者，下次调用重新走 LLM。
#[tokio::test]
async fn spelling_mismatch_not_cached() {
    let (pool, cfg, db_path) = setup().await;
    let mock = MockDeepSeek::new(RUN_XML);
    // 请求 "running"，LLM 返回 spelling "run"
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "running").await;
    let w = r.expect("spelling mismatch must still return the result to requester");
    assert_eq!(w.spelling, "run");
    let cached: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM word_lookup_cache WHERE word = 'running'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        cached, 0,
        "mismatched spelling must not pollute shared cache"
    );
    // 第二次调用：未入缓存 → 重新走 LLM（调用计数 +1）
    let r2 = llm_service::word_lookup(&pool, &cfg, &mock, "138", "running").await;
    assert!(r2.is_ok());
    assert_eq!(
        mock.calls.load(Ordering::SeqCst),
        2,
        "uncached word must hit LLM again"
    );
    cleanup(pool, &db_path).await;
}

/// 顺带：缓存命中但反序列化失败（corrupt cache）时删行自愈并继续走 LLM，而非永久 500。
#[tokio::test]
async fn corrupt_cache_row_self_heals() {
    let (pool, cfg, db_path) = setup().await;
    // 手工写坏 JSON 到缓存表
    sqlx::query(
        "INSERT OR REPLACE INTO word_lookup_cache (word, result_json, created_at) \
         VALUES ('ocean', '{not-valid-json', ?)",
    )
    .bind(Utc::now().timestamp_millis())
    .execute(&pool)
    .await
    .unwrap();
    let mock = MockDeepSeek::new(VALID_XML);
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    let w = r.expect("corrupt cache row must self-heal, not 500");
    assert_eq!(w.spelling, "ocean");
    assert_eq!(mock.calls.load(Ordering::SeqCst), 1);
    // 坏行已删除，且以新查询结果重写
    let stored: String =
        sqlx::query_scalar("SELECT result_json FROM word_lookup_cache WHERE word = 'ocean'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(
        serde_json::from_str::<server::llm::parser::WordLookup>(&stored)
            .unwrap()
            .spelling,
        "ocean",
        "cache row must be rewritten with valid JSON"
    );
    cleanup(pool, &db_path).await;
}

/// Task 2：word_lookup 的 system/user prompt 改从 DB 读取——更新 prompt 表后，
/// LLM 必须收到修改后的内容（DB 化生效的关键用例）。
#[tokio::test]
async fn word_lookup_uses_db_modified_system_prompt() {
    let (pool, cfg, db_path) = setup().await;
    let modified = "You are a modified dictionary assistant.\nRules: strict XML output.";
    sqlx::query("UPDATE prompt SET content = ?, updated_at = ? WHERE key = 'word_lookup_system'")
        .bind(modified)
        .bind(Utc::now().timestamp_millis())
        .execute(&pool)
        .await
        .unwrap();
    let mock = MockDeepSeek::new(VALID_XML);
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    assert!(r.is_ok(), "DB 修改后查词应成功: {:?}", r.err());
    assert_eq!(
        mock.captured_system.lock().unwrap().as_deref(),
        Some(modified),
        "LLM 收到的 system 必须是 DB 修改后的内容"
    );
    let user = mock.captured_user.lock().unwrap().clone().unwrap();
    assert!(
        user.starts_with("Look up the word: ocean"),
        "user prompt 占位替换（{{word}}）: {user}"
    );
    cleanup(pool, &db_path).await;
}
