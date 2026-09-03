// 移植 Rust drivers/deepseek.rs 的调用侧（call_with_retry）+ 剩余部分（driverChat）。
// 注意（R3 裁决）：OpenAI 兼容端点先试 `{base}/chat/completions`，404 回退
// `/v1/chat/completions`（DeepSeek 官方两路皆可；若真机 404 则一次 GET 探活成本）。
import { llmFatal, llmRecoverableExhausted, llmTimeout } from "../response";

export interface LlmCallResult {
  content: string;
  promptTokens: number;
  completionTokens: number;
}

export interface LlmCallError {
  kind: "timeout" | "recoverable" | "fatal";
  message: string;
  retryAfterSecs?: number;
}

/** 带 system/user 的 chat 形态（llmService/路由注入；测试常用 0 参闭包也满足此类型）。 */
export type ChatFn = (system: string, user: string) => Promise<LlmCallResult>;

async function sleepMs(ms: number): Promise<void> {
  await Bun.sleep(ms);
}

/**
 * 重试语义（移植 Dart LlmCaller / Rust call_with_retry）：共 4 次尝试（attempt 0..3），
 * 第 4 次失败才抛 exhausted（timeout→LLM_TIMEOUT / recoverable→LLM_RECOVERABLE_EXHAUSTED）；
 * fatal 立即失败；等待时长优先用 429 的 Retry-After 秒数（clamp 0..30s），
 * 否则指数退避 2s × 2^(n-1) 封顶 10s；硬预算 [budgetMs]：每次尝试以剩余预算截断，
 * 退避等待也计入预算，超预算/总超时 → LLM_TIMEOUT。
 * chat 为无参闭包（system/user 由调用方捕获）。
 */
export async function callWithRetry(
  chat: () => Promise<LlmCallResult>,
  budgetMs: number,
): Promise<LlmCallResult> {
  const deadline = Date.now() + budgetMs;
  for (let attempt = 0; ; attempt++) {
    if (Date.now() >= deadline) throw llmTimeout("LLM timeout");
    const remaining = deadline - Date.now();
    // 尝试级超时：剩余预算截断
    const result = await Promise.race([
      chatWrapper(chat),
      sleepMs(remaining).then(() => ({ kind: "timeout" as const, message: "budget" })),
    ]);
    if (isOk(result)) return result;
    const e = result as LlmCallError;
    if (e.kind === "fatal") throw llmFatal(e.message);
    if (attempt >= 3) {
      if (e.kind === "timeout") throw llmTimeout("LLM timeout");
      throw llmRecoverableExhausted(e.message);
    }
    const wait = e.kind === "recoverable" && e.retryAfterSecs !== undefined
      ? Math.min(e.retryAfterSecs, 30) * 1000
      : Math.min(2000 * 2 ** attempt, 10_000);
    if (Date.now() + wait >= deadline) throw llmTimeout("LLM timeout");
    await sleepMs(wait);
  }
}

/** 有效载荷为 LlmCallError（chat 内部 throw 的错误对象）→ 原样透传；其余 reject（网络等）→ timeout。 */
function isLlmCallError(e: unknown): e is LlmCallError {
  if (typeof e !== "object" || e === null) return false;
  const k = (e as { kind?: unknown }).kind;
  return k === "timeout" || k === "recoverable" || k === "fatal";
}

function chatWrapper(chat: () => Promise<LlmCallResult>): Promise<LlmCallResult | LlmCallError> {
  return chat().catch((e: unknown) =>
    isLlmCallError(e) ? e : ({ kind: "timeout" as const, message: "network" }),
  );
}

function isOk(r: LlmCallResult | LlmCallError): r is LlmCallResult {
  return typeof (r as LlmCallResult).content === "string";
}

/** driverChat 的 LLM 端点配置（由路由 defaultChat 用 ServerConfig 的 LLM 字段组装）。 */
export type FetchLike = (url: string, init?: RequestInit & { proxy?: string }) => Promise<Response>;

export interface LlmDriverOptions {
  baseUrl: string;
  apiKey: string;
  model: string;
  proxyUrl?: string;
  /** 单请求兜底超时（对齐 Rust reqwest client timeout；预算级截断由 callWithRetry 负责）。 */
  timeoutMs?: number;
  /** 测试注入的 fetch 实现（Bun 的全局 fetch 亦满足本类型）。 */
  fetchFn?: FetchLike;
}

const DEFAULT_TIMEOUT_MS = 90_000;

/**
 * OpenAI 兼容 `POST {base}/chat/completions` 驱动（供 llmService 闭包包装为无参 chat）。
 * 错误分类（对齐 Dart LlmErrorClassifier / Rust DeepSeekClient）：
 * 400/401/403 → fatal；429 → recoverable(retryAfterSecs)；5xx/其余 → recoverable；
 * send 失败（网络/超时，一切）→ timeout；成功：choices[0].message.content + usage（usage 缺省 0）。
 */
export async function driverChat(
  opts: LlmDriverOptions,
  system: string,
  user: string,
): Promise<LlmCallResult> {
  const base = opts.baseUrl.trim().replace(/\/+$/, "");
  const fetchFn: FetchLike = opts.fetchFn ?? fetch;
  const body = JSON.stringify({
    model: opts.model,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
    stream: false,
  });
  const init: RequestInit = {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${opts.apiKey}`,
    },
    body,
    signal: AbortSignal.timeout(opts.timeoutMs ?? DEFAULT_TIMEOUT_MS),
  };
  // Bun fetch 的 proxy 选项（对齐引擎 createLLM 的 makeProxyFetch）
  const doFetch = (url: string): Promise<Response> =>
    opts.proxyUrl ? fetchFn(url, { ...init, proxy: opts.proxyUrl }) : fetchFn(url, init);

  const send = async (path: string): Promise<Response> => {
    try {
      return await doFetch(`${base}${path}`);
    } catch (e) {
      // 对齐 Rust drivers/deepseek.rs:85：send() 的一切失败（超时信号、DNS、拒连、TLS……）
      // 统一归 LlmCallError::Timeout（App 端映射 LLM_TIMEOUT 504），而非 recoverable。
      throw { kind: "timeout" as const, message: String((e as Error)?.message ?? e) };
    }
  };

  // send 参数为路径（相对 base），避免与 doFetch 的 base 拼接重复
  let resp = await send("/chat/completions");
  if (resp.status === 404) {
    // R3：先试 /chat/completions；404 回退 /v1/chat/completions
    resp = await send("/v1/chat/completions");
  }

  if (!resp.ok) {
    const retryAfterSecs = parseRetryAfter(resp.headers.get("retry-after"));
    const msg = `${resp.status}: ${await resp.text().catch(() => "")}`;
    if (resp.status === 400 || resp.status === 401 || resp.status === 403) {
      throw { kind: "fatal" as const, message: msg };
    }
    throw { kind: "recoverable" as const, message: msg, retryAfterSecs };
  }

  let parsed: { choices?: { message?: { content?: string | null } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number } };
  try {
    parsed = await resp.json();
  } catch (e) {
    throw { kind: "recoverable" as const, message: String((e as Error)?.message ?? e) };
  }
  const content = parsed.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw { kind: "recoverable" as const, message: "empty choices" };
  }
  const u = parsed.usage;
  return {
    content,
    promptTokens: u?.prompt_tokens ?? 0,
    completionTokens: u?.completion_tokens ?? 0,
  };
}

/** Retry-After header（秒）；缺失/非数字 → undefined（交由调用方走指数退避）。 */
function parseRetryAfter(header: string | null): number | undefined {
  if (!header) return undefined;
  const n = Number(header);
  return Number.isFinite(n) && n >= 0 ? n : undefined;
}
