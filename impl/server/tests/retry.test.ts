// tests/retry.test.ts
// 注：brief Step 3 的指数退避测试按语义实等（2+4+8=14s），超出 bun 默认 5s per-test 超时，
// 文件级放宽到 30s（setDefaultTimeout 只影响本文件）。
import { setDefaultTimeout, describe, expect, test } from "bun:test";
import { callWithRetry, driverChat, type LlmCallError, type LlmDriverOptions } from "../src/llm/retry";

setDefaultTimeout(30_000);

function err(kind: LlmCallError["kind"], retryAfterSecs?: number): LlmCallError {
  return { kind, message: "err", retryAfterSecs };
}

describe("callWithRetry", () => {
  test("首次成功直接返回", async () => {
    const r = await callWithRetry(async () => ({ content: "ok", promptTokens: 1, completionTokens: 2 }), 5000);
    expect(r.content).toBe("ok");
  });
  test("recoverable 重试后成功（4 次上限内）", async () => {
    let n = 0;
    const r = await callWithRetry(async () => {
      n++;
      if (n < 3) throw err("recoverable");
      return { content: "ok", promptTokens: 1, completionTokens: 1 };
    }, 60_000);
    expect(r.content).toBe("ok");
    expect(n).toBe(3);
  });
  test("recoverable 4 次尝试耗尽 → LLM_RECOVERABLE_EXHAUSTED", async () => {
    let n = 0;
    await expect(
      callWithRetry(async () => { n++; throw err("recoverable"); }, 60_000),
    ).rejects.toMatchObject({ errorCode: "LLM_RECOVERABLE_EXHAUSTED", status: 502 });
    expect(n).toBe(4);
  });
  test("fatal 立即失败不重试", async () => {
    let n = 0;
    await expect(
      callWithRetry(async () => { n++; throw err("fatal"); }, 60_000),
    ).rejects.toMatchObject({ errorCode: "LLM_FATAL" });
    expect(n).toBe(1);
  });
  test("总预算耗尽 → LLM_TIMEOUT", async () => {
    let n = 0;
    await expect(
      callWithRetry(async () => { n++; await Bun.sleep(100); throw err("timeout"); }, 250),
    ).rejects.toMatchObject({ errorCode: "LLM_TIMEOUT" });
    expect(n).toBeLessThanOrEqual(4);
  });
  test("Retry-After 建议等待超预算 → LLM_TIMEOUT 立即放弃（不实等）", async () => {
    let n = 0;
    await expect(
      callWithRetry(async () => { n++; throw err("recoverable", 999); }, 25_000),
    ).rejects.toMatchObject({ errorCode: "LLM_TIMEOUT" });
    expect(n).toBe(1); // 等待（clamp 后 30s）> 剩余预算 → 不重试直接超时
  });
});

/** driverChat 错误分类（Interfaces：400/401/403→fatal、429→recoverable(retryAfter)、
 *  5xx/网络/解析失败→recoverable、超时→timeout；usage 缺省 0；R3：/chat/completions 404 回退 /v1）。 */
function opts(fetchFn: (url: string) => Promise<Response>): LlmDriverOptions {
  return { baseUrl: "https://llm.example.com/", apiKey: "k", model: "m", fetchFn };
}

function chatResp(content: string, usage?: { prompt_tokens: number; completion_tokens: number }): Response {
  return Response.json({ choices: [{ message: { content } }], usage });
}

describe("driverChat", () => {
  test("成功：content + usage 透传，baseUrl 尾斜杠去除", async () => {
    const hits: string[] = [];
    const r = await driverChat(opts(async (url) => {
      hits.push(String(url));
      return chatResp("hi", { prompt_tokens: 7, completion_tokens: 3 });
    }), "sys", "usr");
    expect(hits).toEqual(["https://llm.example.com/chat/completions"]);
    expect(r).toEqual({ content: "hi", promptTokens: 7, completionTokens: 3 });
  });
  test("usage 缺省 → 0", async () => {
    const r = await driverChat(opts(async () => chatResp("hi")), "s", "u");
    expect(r).toEqual({ content: "hi", promptTokens: 0, completionTokens: 0 });
  });
  test("400/401/403 → fatal", async () => {
    for (const status of [400, 401, 403]) {
      await expect(driverChat(opts(async () => new Response("bad", { status })), "s", "u"))
        .rejects.toMatchObject({ kind: "fatal", message: `${status}: bad` });
    }
  });
  test("429 → recoverable + Retry-After 秒数", async () => {
    await expect(driverChat(opts(async () => new Response("rate", { status: 429, headers: { "retry-after": "17" } })), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable", retryAfterSecs: 17 });
  });
  test("429 无/非法 Retry-After → recoverable 无秒数", async () => {
    await expect(driverChat(opts(async () => new Response("rate", { status: 429 })), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable", retryAfterSecs: undefined });
    await expect(driverChat(opts(async () => new Response("rate", { status: 429, headers: { "retry-after": "abc" } })), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable", retryAfterSecs: undefined });
  });
  test("5xx / 其余非成功 → recoverable", async () => {
    for (const status of [500, 502, 503]) {
      await expect(driverChat(opts(async () => new Response("boom", { status })), "s", "u"))
        .rejects.toMatchObject({ kind: "recoverable", message: `${status}: boom` });
    }
  });
  test("解析失败 / 空 choices / 缺 content → recoverable", async () => {
    await expect(driverChat(opts(async () => new Response("not json", { status: 200 })), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable" });
    await expect(driverChat(opts(async () => Response.json({ choices: [] })), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable" });
    await expect(driverChat(opts(async () => Response.json({ choices: [{ message: {} }] })), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable" });
  });
  test("网络错误 → recoverable；AbortError → timeout", async () => {
    await expect(driverChat(opts(async () => { throw new TypeError("fetch failed"); }), "s", "u"))
      .rejects.toMatchObject({ kind: "recoverable" });
    await expect(driverChat(opts(async () => { throw new DOMException("aborted", "AbortError"); }), "s", "u"))
      .rejects.toMatchObject({ kind: "timeout" });
  });
  test("R3 404 回退：/chat/completions 404 → /v1/chat/completions 成功", async () => {
    const hits: string[] = [];
    const r = await driverChat(opts(async (url) => {
      hits.push(String(url));
      if (String(url) === "https://llm.example.com/chat/completions") return new Response("nf", { status: 404 });
      return chatResp("fallback-ok", { prompt_tokens: 1, completion_tokens: 2 });
    }), "s", "u");
    expect(hits).toEqual([
      "https://llm.example.com/chat/completions",
      "https://llm.example.com/v1/chat/completions",
    ]);
    expect(r.content).toBe("fallback-ok");
  });
});
