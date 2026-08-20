use crate::config::Config;
use crate::response::AppError;
use async_trait::async_trait;
use serde::Deserialize;

pub struct DeepSeekResponse {
    pub content: String,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
}

#[derive(Debug)]
pub enum LlmCallError {
    Timeout,
    /// 可恢复错误：错误文本 + 服务端建议的 Retry-After 秒数（429 时通常有值）。
    Recoverable(String, Option<u64>),
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
            // 单请求兜底超时（防裸调用挂死，对齐 llm_timeout_secs=90 的既有默认值）；
            // 按剩余预算的尝试级超时由 call_with_retry 的 tokio::time::timeout 负责，
            // 二者不冲突（预算内的截断必然先到）。
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(cfg.llm_timeout_secs))
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
            // 先读头再消费 body（resp.text() 会取走响应体）
            let retry_after = resp
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse::<u64>().ok());
            let msg = resp.text().await.unwrap_or_default();
            // 移植 Dart LlmErrorClassifier：400/401/403 → Fatal（立即失败），
            // 429/5xx/其余 → Recoverable（Retry-After 交由 call_with_retry 消费）
            return match status.as_u16() {
                400 | 401 | 403 => Err(LlmCallError::Fatal(format!("{}: {}", status, msg))),
                _ => Err(LlmCallError::Recoverable(
                    format!("{}: {}", status, msg),
                    retry_after,
                )),
            };
        }
        let parsed: ChatResp = resp
            .json()
            .await
            .map_err(|e| LlmCallError::Recoverable(e.to_string(), None))?;
        let content = parsed
            .choices
            .into_iter()
            .next()
            .and_then(|c| c.message.content)
            .ok_or_else(|| LlmCallError::Recoverable("empty choices".to_string(), None))?;
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

/// 重试语义（移植 Dart LlmCaller）：`llmMaxRetries=3` = 1 初试 + 3 重试 = 4 次总尝试，
/// 第 4 次失败才抛 exhausted（携带最后错误文本）；Fatal 立即失败；等待时长优先用
/// 429 的 Retry-After 秒数（clamp 0..30s），否则指数退避 2s*2^(n-1) 封顶 10s；
/// 硬预算 [budget_secs]：每次尝试以剩余预算做 tokio::time::timeout，且退避等待
/// 也计入预算，超时/预算耗尽 → AppError::LlmTimeout。
pub async fn call_with_retry(
    api: &dyn DeepSeekApi,
    system: &str,
    user: &str,
    budget_secs: u64,
) -> Result<DeepSeekResponse, AppError> {
    let deadline = tokio::time::Instant::now() + tokio::time::Duration::from_secs(budget_secs);
    let mut attempt = 0u32; // 0..=3 共 4 次尝试
    loop {
        if tokio::time::Instant::now() >= deadline {
            return Err(AppError::LlmTimeout("LLM timeout".into()));
        }
        let remaining = deadline - tokio::time::Instant::now();
        let wait = match tokio::time::timeout(remaining, api.chat(system, user)).await {
            Ok(Ok(r)) => return Ok(r),
            Ok(Err(LlmCallError::Fatal(msg))) => return Err(AppError::LlmFatal(msg)),
            // 尝试级超时（tokio 截断）或 chat 内部超时/网络错误：可重试，
            // 但预算已随尝试扣除，退避前仍需预算检查（预算耗尽 → LlmTimeout）
            Ok(Err(LlmCallError::Timeout)) | Err(_) => {
                if attempt >= 3 {
                    return Err(AppError::LlmTimeout("LLM timeout".into()));
                }
                backoff(attempt)
            }
            Ok(Err(LlmCallError::Recoverable(msg, retry_after))) => {
                if attempt >= 3 {
                    // 最后错误文本不丢弃（对照 Dart exhausted 携带 cause）
                    return Err(AppError::LlmRecoverableExhausted(msg));
                }
                match retry_after {
                    Some(secs) => std::time::Duration::from_secs(secs.min(30)),
                    None => backoff(attempt),
                }
            }
        };
        attempt += 1;
        // 退避/Retry-After 等待也计入总预算（Dart：waitRemaining 检查）
        if tokio::time::Instant::now() + wait >= deadline {
            return Err(AppError::LlmTimeout("LLM timeout".into()));
        }
        tokio::time::sleep(wait).await;
    }
}

/// 指数退避：2s × 2^(n-1)，封顶 10s（n = 本次失败尝试的序号，1 起）。
fn backoff(attempt: u32) -> std::time::Duration {
    std::time::Duration::from_millis((2000u64 << attempt).min(10_000))
}
