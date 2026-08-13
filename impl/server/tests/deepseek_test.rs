use server::drivers::deepseek::{DeepSeekApi, DeepSeekResponse, LlmCallError, call_with_retry};
use std::sync::atomic::{AtomicUsize, Ordering};

struct FlakyApi {
    calls: AtomicUsize,
}
#[async_trait::async_trait]
impl DeepSeekApi for FlakyApi {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        let n = self.calls.fetch_add(1, Ordering::SeqCst);
        if n < 2 {
            Err(LlmCallError::Recoverable("429".into()))
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
    assert_eq!(api.calls.load(Ordering::SeqCst), 3);
}

struct AlwaysFatal;
#[async_trait::async_trait]
impl DeepSeekApi for AlwaysFatal {
    async fn chat(&self, _s: &str, _u: &str) -> Result<DeepSeekResponse, LlmCallError> {
        Err(LlmCallError::Fatal("401".into()))
    }
}

#[tokio::test]
async fn fatal_error_immediately_fails() {
    let r = call_with_retry(&AlwaysFatal, "s", "u", 90).await;
    assert!(r.is_err());
}
