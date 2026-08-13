use crate::config::Config;
use crate::response::AppError;
use async_trait::async_trait;
use serde::Deserialize;

pub struct DeepSeekResponse {
    pub content: String,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
}

pub enum LlmCallError {
    Timeout,
    Recoverable(String),
    Fatal(String),
}

#[async_trait]
pub trait DeepSeekApi: Send + Sync {
    async fn chat(&self, system: &str, user: &str) -> Result<DeepSeekResponse, LlmCallError>;
}

#[derive(Deserialize)]
struct ChatResp {
    choices: Vec<Choice>,
    usage: Option<Usage>,
}
#[derive(Deserialize)]
struct Choice {
    message: Message,
}
#[derive(Deserialize)]
struct Message {
    content: Option<String>,
}
#[derive(Deserialize)]
struct Usage {
    prompt_tokens: u64,
    completion_tokens: u64,
}

pub struct DeepSeekClient {
    http: reqwest::Client,
    base: String,
    key: String,
    model: String,
}

impl DeepSeekClient {
    pub fn new(cfg: &Config) -> anyhow::Result<Self> {
        Ok(Self {
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(60))
                .build()?,
            base: cfg.deepseek_base_url.trim_end_matches('/').to_string(),
            key: cfg.deepseek_api_key.clone(),
            model: cfg.deepseek_model.clone(),
        })
    }
}

#[async_trait]
impl DeepSeekApi for DeepSeekClient {
    async fn chat(&self, system: &str, user: &str) -> Result<DeepSeekResponse, LlmCallError> {
        let body = serde_json::json!({
            "model": self.model,
            "messages": [
                { "role": "system", "content": system },
                { "role": "user", "content": user },
            ],
            "stream": false,
        });
        let resp = self
            .http
            .post(format!("{}/v1/chat/completions", self.base))
            .bearer_auth(&self.key)
            .json(&body)
            .send()
            .await
            .map_err(|_| LlmCallError::Timeout)?;
        let status = resp.status();
        if !status.is_success() {
            let msg = resp.text().await.unwrap_or_default();
            return match status.as_u16() {
                401 | 403 => Err(LlmCallError::Fatal(format!("{}: {}", status, msg))),
                _ => Err(LlmCallError::Recoverable(format!("{}: {}", status, msg))),
            };
        }
        let parsed: ChatResp = resp
            .json()
            .await
            .map_err(|e| LlmCallError::Recoverable(e.to_string()))?;
        let content = parsed
            .choices
            .into_iter()
            .next()
            .and_then(|c| c.message.content)
            .ok_or_else(|| LlmCallError::Recoverable("empty choices".to_string()))?;
        let u = parsed.usage.unwrap_or(Usage {
            prompt_tokens: 0,
            completion_tokens: 0,
        });
        Ok(DeepSeekResponse {
            content,
            prompt_tokens: u.prompt_tokens,
            completion_tokens: u.completion_tokens,
        })
    }
}

/// 重试语义（移植 Dart LlmCaller）：3 次尝试、指数退避 2s*2^(n-1) 封顶 10s、
/// 总预算 [budget_secs] 耗尽 → AppError::LlmTimeout；Fatal → LlmFatal。
pub async fn call_with_retry(
    api: &dyn DeepSeekApi,
    system: &str,
    user: &str,
    budget_secs: u64,
) -> Result<DeepSeekResponse, AppError> {
    let deadline = tokio::time::Instant::now() + tokio::time::Duration::from_secs(budget_secs);
    let mut attempt = 0u32;
    loop {
        match api.chat(system, user).await {
            Ok(r) => return Ok(r),
            Err(LlmCallError::Fatal(msg)) => return Err(AppError::LlmFatal(msg)),
            Err(LlmCallError::Timeout) => {
                if tokio::time::Instant::now() >= deadline || attempt >= 2 {
                    return Err(AppError::LlmTimeout("LLM timeout".into()));
                }
            }
            Err(LlmCallError::Recoverable(_)) => {
                if attempt >= 2 {
                    return Err(AppError::LlmRecoverableExhausted(
                        "LLM retries exhausted".into(),
                    ));
                }
            }
        }
        let wait = std::time::Duration::from_millis((2000u64 << attempt).min(10_000));
        attempt += 1;
        if tokio::time::Instant::now() + wait >= deadline {
            return Err(AppError::LlmTimeout("LLM timeout".into()));
        }
        tokio::time::sleep(wait).await;
    }
}
