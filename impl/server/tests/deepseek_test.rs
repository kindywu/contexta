use server::config::Config;
use server::drivers::deepseek::{
    DeepSeekApi, DeepSeekClient, DeepSeekResponse, LlmCallError, call_with_retry,
};
use server::response::AppError;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

fn test_config(base_url: &str) -> Config {
    Config {
        port: 0,
        db_path: "unused.db".into(),
        jwt_secret: "x".repeat(32),
        deepseek_api_key: "test-key".into(),
        deepseek_base_url: base_url.into(),
        deepseek_model: "test-model".into(),
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

// ---------- 重试编排（trait mock） ----------

/// 前 3 次可恢复失败、第 4 次成功：llmMaxRetries=3 = 1 初试 + 3 重试 = 4 次总尝试。
struct FlakyApi {
    calls: AtomicUsize,
}
#[async_trait::async_trait]
impl DeepSeekApi for FlakyApi {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        let n = self.calls.fetch_add(1, Ordering::SeqCst);
        if n < 3 {
            Err(LlmCallError::Recoverable("429".into(), None))
        } else {
            Ok(DeepSeekResponse {
                content: "ok".into(),
                prompt_tokens: 1,
                completion_tokens: 1,
            })
        }
    }
}

#[tokio::test]
async fn retries_recoverable_errors_then_succeeds() {
    let api = FlakyApi {
        calls: AtomicUsize::new(0),
    };
    let r = call_with_retry(&api, "s", "u", 90).await.unwrap();
    assert_eq!(r.content, "ok");
    assert_eq!(api.calls.load(Ordering::SeqCst), 4);
}

struct AlwaysFatal {
    calls: AtomicUsize,
}
#[async_trait::async_trait]
impl DeepSeekApi for AlwaysFatal {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        Err(LlmCallError::Fatal("401".into()))
    }
}

#[tokio::test]
async fn fatal_error_immediately_fails() {
    let api = AlwaysFatal {
        calls: AtomicUsize::new(0),
    };
    let r = call_with_retry(&api, "s", "u", 90).await;
    assert!(matches!(r, Err(AppError::LlmFatal(_))));
    assert_eq!(api.calls.load(Ordering::SeqCst), 1);
}

/// 429 场景：Recoverable 携带 Retry-After 秒数，等待时长应取 Retry-After（1s）而非退避。
struct RetryAfterApi {
    calls: AtomicUsize,
}
#[async_trait::async_trait]
impl DeepSeekApi for RetryAfterApi {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        let n = self.calls.fetch_add(1, Ordering::SeqCst);
        if n < 2 {
            Err(LlmCallError::Recoverable("429".into(), Some(1)))
        } else {
            Ok(DeepSeekResponse {
                content: "ok".into(),
                prompt_tokens: 1,
                completion_tokens: 1,
            })
        }
    }
}

#[tokio::test]
async fn retry_after_controls_wait() {
    let api = RetryAfterApi {
        calls: AtomicUsize::new(0),
    };
    let start = tokio::time::Instant::now();
    let r = call_with_retry(&api, "s", "u", 90).await.unwrap();
    assert_eq!(r.content, "ok");
    assert_eq!(api.calls.load(Ordering::SeqCst), 3);
    // 2 次 1s 等待 ≈ 2s；若走指数退避（2s+4s=6s）则 ≥ 6s——证明 Retry-After 生效
    assert!(start.elapsed() < Duration::from_secs(5));
}

/// 单次尝试远超剩余预算：tokio::time::timeout 必须在预算处截断（硬预算）。
struct SlowApi {
    calls: AtomicUsize,
    sleep_secs: u64,
}
#[async_trait::async_trait]
impl DeepSeekApi for SlowApi {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_secs(self.sleep_secs)).await;
        Ok(DeepSeekResponse {
            content: "late".into(),
            prompt_tokens: 1,
            completion_tokens: 1,
        })
    }
}

#[tokio::test]
async fn hard_budget_cuts_off_slow_attempt() {
    let api = SlowApi {
        calls: AtomicUsize::new(0),
        sleep_secs: 100,
    };
    let start = tokio::time::Instant::now();
    let r = call_with_retry(&api, "s", "u", 3).await;
    assert!(matches!(r, Err(AppError::LlmTimeout(_))));
    assert_eq!(api.calls.load(Ordering::SeqCst), 1);
    assert!(start.elapsed() < Duration::from_secs(10)); // 未被 100s 挂住
}

/// 可恢复重试被预算截断：每次尝试 1.5s、预算 4s → 第 2 次尝试后退避超预算 → LlmTimeout
///（而非继续重试到 exhausted），尝试数受预算约束。
struct SlowRecoverableApi {
    calls: AtomicUsize,
}
#[async_trait::async_trait]
impl DeepSeekApi for SlowRecoverableApi {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(1500)).await;
        Err(LlmCallError::Recoverable("slow".into(), None))
    }
}

#[tokio::test]
async fn budget_exhaustion_beats_retry() {
    let api = SlowRecoverableApi {
        calls: AtomicUsize::new(0),
    };
    let r = call_with_retry(&api, "s", "u", 4).await;
    assert!(matches!(r, Err(AppError::LlmTimeout(_))));
    assert_eq!(api.calls.load(Ordering::SeqCst), 2);
}

// ---------- DeepSeekClient 真实 HTTP（httpmock） ----------

#[tokio::test]
async fn http_400_is_fatal_single_attempt() {
    let server = httpmock::MockServer::start();
    let mock = server.mock(|when, then| {
        when.method(httpmock::Method::POST)
            .path("/v1/chat/completions");
        then.status(400).body("{\"error\":\"bad request\"}");
    });
    let client = DeepSeekClient::new(&test_config(&server.base_url())).unwrap();
    // 400 分类为 Fatal → call_with_retry 立即失败且只调用 1 次
    let r = call_with_retry(&client, "s", "u", 30).await;
    assert!(matches!(r, Err(AppError::LlmFatal(_))));
    mock.assert_calls(1);
}

#[tokio::test]
async fn http_429_carries_retry_after() {
    let server = httpmock::MockServer::start();
    let mock = server.mock(|when, then| {
        when.method(httpmock::Method::POST)
            .path("/v1/chat/completions");
        then.status(429)
            .header("retry-after", "2")
            .body("{\"error\":\"rate limited\"}");
    });
    let client = DeepSeekClient::new(&test_config(&server.base_url())).unwrap();
    let r = client.chat("s", "u").await;
    assert!(matches!(r, Err(LlmCallError::Recoverable(msg, Some(2))) if msg.contains("429")));
    mock.assert_calls(1);
}

#[tokio::test]
async fn http_200_parses_response() {
    let server = httpmock::MockServer::start();
    let mock = server.mock(|when, then| {
        when.method(httpmock::Method::POST).path("/v1/chat/completions");
        then.status(200)
            .header("content-type", "application/json")
            .body(r#"{"choices":[{"message":{"content":"hello"}}],"usage":{"prompt_tokens":5,"completion_tokens":7}}"#);
    });
    let client = DeepSeekClient::new(&test_config(&server.base_url())).unwrap();
    let r = client.chat("s", "u").await.unwrap();
    assert_eq!(r.content, "hello");
    assert_eq!(r.prompt_tokens, 5);
    assert_eq!(r.completion_tokens, 7);
    mock.assert_calls(1);
}
