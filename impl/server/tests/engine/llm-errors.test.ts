// tests/engine/llm-errors.test.ts
// 402（上游余额不足）在引擎侧的三件事，全部离线（stub fetch 直接回 402，不真发网络请求）：
// 1) 契约：上游 402 经 @langchain/openai 抛出时带 `status=402`、message = "402 <上游 error.message>"
//    ——generateNode 的分类、每日任务跳过补跑、LangGraph 节点级不重试，全建立在这个字段上；
// 2) 分类：402 → billing（不是"结构要求"：它根本没走到内容解析，HTTP 层就被拒了）；
// 3) 文案：`BILLING_REASON_PREFIX` + 上游原文（管理端「异常槽位」直接展示，充值后手动重跑）。
import { expect, test } from "bun:test";
import { ChatOpenAI } from "@langchain/openai";
import { callLLMStructured, isInsufficientBalance, type LLM } from "../../src/engine/llm";
import {
  BILLING_REASON_PREFIX,
  classifyGenerateFailure,
  generateNode,
} from "../../src/engine/graph/nodes";
import { GenerateResult } from "../../src/engine/schema";

const REQ_ID = "f0a788af-17f9-4e9e-99a9-0fc06142803b";

/** DeepSeek 402 响应体（error.message 里带 request_id）。 */
const BALANCE_ERROR_BODY = JSON.stringify({
  error: {
    message: `Insufficient Balance (request_id: ${REQ_ID})`,
    type: "unknown_error",
    param: null,
    code: "invalid_request_error",
  },
});

/** 200 响应体（用来看"内容层"失败与 402 的区别）。 */
function okBody(content: string): string {
  return JSON.stringify({
    id: "chatcmpl-test",
    choices: [{ index: 0, finish_reason: "stop", message: { role: "assistant", content } }],
    usage: { prompt_tokens: 1, completion_tokens: 1 },
  });
}

/** stub fetch：固定回给定 body/status，并记录请求次数。 */
function stubFetch(body: string, status: number) {
  const calls: string[] = [];
  const fn = (async (input: RequestInfo | URL) => {
    calls.push(String(input));
    return new Response(body, {
      status,
      headers: { "content-type": "application/json", "x-request-id": REQ_ID },
    });
  }) as unknown as typeof fetch;
  return { fn, calls };
}

function stubLLM(f: typeof fetch): LLM {
  return new ChatOpenAI({
    model: "deepseek-chat",
    apiKey: "sk-test",
    maxTokens: 256,
    configuration: { baseURL: "https://api.deepseek.com", fetch: f },
  }) as unknown as LLM;
}

/** 跑一次结构化调用并捕获抛错（不抛则返回 undefined）。 */
async function catchStructured(llm: LLM): Promise<unknown> {
  try {
    await callLLMStructured(llm, "只输出 json", "写一篇", GenerateResult, "generateB");
    return undefined;
  } catch (e) {
    return e;
  }
}

test("isInsufficientBalance：认 SDK / driverChat / 引擎包装三种形态，不认裸数字", () => {
  // SDK（@langchain/openai）与 driverChat 两种抛出形态
  expect(isInsufficientBalance(`402 Insufficient Balance (request_id: ${REQ_ID})`)).toBe(true);
  expect(isInsufficientBalance('402: {"error":{"message":"Insufficient Balance"}}')).toBe(true);
  // 引擎包装后（generateNode 的 reason 落库形态）
  expect(
    isInsufficientBalance(`生成结果不符合结构要求: 402 Insufficient Balance (request_id: ${REQ_ID})`),
  ).toBe(true);
  // 只有中文措辞、没有状态码
  expect(isInsufficientBalance("账户余额不足，请充值")).toBe(true);
  // 反例：无关错误 / 裸数字（request_id、毫秒数）/ 空值
  expect(isInsufficientBalance("500 Internal Server Error")).toBe(false);
  expect(isInsufficientBalance("request_id: a402b3c4-0000-0000")).toBe(false);
  expect(isInsufficientBalance("timeout after 4020ms")).toBe(false);
  expect(isInsufficientBalance("")).toBe(false);
  expect(isInsufficientBalance(null)).toBe(false);
  expect(isInsufficientBalance(undefined)).toBe(false);
});

test("上游 402：抛错带 status=402 + 上游原文（只发 1 次请求），分类为 billing", async () => {
  const { fn, calls } = stubFetch(BALANCE_ERROR_BODY, 402);
  const thrown = await catchStructured(stubLLM(fn));
  expect(thrown).toBeInstanceOf(Error);

  const err = thrown as Error & { status?: number };
  expect(err.status).toBe(402); // 分类/节点级不重试都靠这个字段（见 graph-retry.test.ts）
  expect(err.message).toBe(`402 Insufficient Balance (request_id: ${REQ_ID})`);
  expect(classifyGenerateFailure(err)).toBe("billing");
  expect(calls).toHaveLength(1); // 402 不重试（SDK 侧亦不重试）
});

test("generateNode：402 → error 终态 +「余额不足…充值后重跑」文案（不再叫结构要求）", async () => {
  const { fn } = stubFetch(BALANCE_ERROR_BODY, 402);
  const state = {
    runDate: "2026-09-17",
    difficulty: "HIGH",
    category: "academic_abstract",
    topic: "probe",
    recentTitles: [],
  } as unknown as Parameters<typeof generateNode>[0];
  const deps = {
    llm: stubLLM(fn),
    sitesByCategory: {},
    rng: () => 0,
  } as unknown as Parameters<typeof generateNode>[1];

  const update = (await generateNode(state, deps, { path: "B" })) as {
    outcome?: string;
    reason?: string;
  };

  expect(update.outcome).toBe("error");
  expect(update.reason).toContain(BILLING_REASON_PREFIX);
  expect(update.reason).toContain("402 Insufficient Balance"); // 上游原文保留，便于追溯
  expect(update.reason).not.toContain("结构");
});

test("回归：200 但内容不合规仍按内容层分类（billing 判定不抢内容层错误）", async () => {
  const cases: [string, "whitespace" | "struct"][] = [
    ["   ", "whitespace"], // 空白弃答（jsonMode 解析失败：Unexpected EOF）
    ["I'm sorry, I can't write this article.", "struct"], // 拒答话术散文（旧形态）
  ];
  for (const [content, expected] of cases) {
    const { fn } = stubFetch(okBody(content), 200);
    expect(classifyGenerateFailure(await catchStructured(stubLLM(fn)))).toBe(expected);
  }
});
