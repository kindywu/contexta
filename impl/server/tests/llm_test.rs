use server::config::Config;
use server::db;
use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError};
use server::response::AppError;
use server::services::llm_service;
use std::sync::Arc;
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
}
#[async_trait::async_trait]
impl DeepSeekApi for MockDeepSeek {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
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

#[tokio::test]
async fn first_call_hits_llm_second_call_cached() {
    let (pool, cfg, db_path) = setup().await;
    let mock = MockDeepSeek {
        calls: Arc::new(AtomicUsize::new(0)),
        content: VALID_XML.to_string(),
    };
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
    let mock = MockDeepSeek {
        calls: Arc::new(AtomicUsize::new(0)),
        content: VALID_XML.to_string(),
    };
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
    let mock = MockDeepSeek {
        calls: Arc::new(AtomicUsize::new(0)),
        content: VALID_XML.to_string(),
    };
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
    let mock = MockDeepSeek {
        calls: Arc::new(AtomicUsize::new(0)),
        content: "not xml at all".to_string(),
    };
    let r = llm_service::word_lookup(&pool, &cfg, &mock, "138", "ocean").await;
    assert!(
        matches!(r, Err(AppError::PipelineBlocking(_))),
        "unparseable LLM output must be PipelineBlocking"
    );
    cleanup(pool, &db_path).await;
}
