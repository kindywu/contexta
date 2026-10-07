import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";
import type { RetryPolicy } from "@langchain/langgraph";
import { loadConfig } from "../../src/engine/config";
import { generateArticle } from "../../src/engine/graph";
import { DEFAULT_NODE_RETRY_POLICY, shouldRetryValidate } from "../../src/engine/graph/graph";
import { FakeLLM } from "./fake-llm";

/** 临时隔离测试配置（checkpoint 也必须隔离：threadId 确定值会交叉污染）。 */
function testConfig() {
  const dir = mkdtempSync(join(tmpdir(), "ap-graph-retry-"));
  return { ...loadConfig(), checkpointPath: join(dir, "cp.sqlite") };
}

test("shouldRetryValidate: 仅违规且轮数未满时返回 true", () => {
  expect(
    shouldRetryValidate({ outcome: "rejected", genAttempts: 1 } as never, 3),
  ).toBe(true);
  expect(
    shouldRetryValidate({ outcome: "rejected", genAttempts: 3 } as never, 3),
  ).toBe(false); // 第 3 轮(封顶)违规 → 终态 rejected
  expect(
    shouldRetryValidate({ outcome: "success", genAttempts: 2 } as never, 3),
  ).toBe(false);
  expect(
    shouldRetryValidate({ outcome: "rejected", genAttempts: 1 } as never, 2),
  ).toBe(true);
});

test("validateB 违规自动重试：前两轮违规反馈进入下一次生成，第 3 轮通过 → success", async () => {
  const fake = new FakeLLM([
    [{ ruleId: "unverified", message: "M1-STATISTIC_UNVERIFIABLE" }],
    [{ ruleId: "unverified", message: "M2-LETTER_MISATTRIBUTED" }],
    null,
  ]);
  const res = await generateArticle({
    runDate: "2026-08-29",
    difficulty: "HIGH",
    threadId: "retry-test-1",
    config: testConfig(),
    llm: fake,
  });
  expect(res.outcome).toBe("success");
  expect(res.genAttempts).toBe(3);
  expect(fake.generatePrompts).toHaveLength(3);
  expect(fake.validateCalls).toBe(3);
  // 违规反馈确实带到了下一次 LLM 请求
  expect(fake.generatePrompts[1]).toContain("REVISION REQUIRED");
  expect(fake.generatePrompts[1]).toContain("M1-STATISTIC_UNVERIFIABLE");
  expect(fake.generatePrompts[2]).toContain("M2-LETTER_MISATTRIBUTED");
});

test("validateB 连续 3 轮违规 → rejected 终态（生成/校验各 3 次）", async () => {
  const fake = new FakeLLM([
    [{ ruleId: "unverified", message: "X" }],
    [{ ruleId: "unverified", message: "X" }],
    [{ ruleId: "unverified", message: "X" }],
  ]);
  const res = await generateArticle({
    runDate: "2026-08-29",
    difficulty: "HIGH",
    threadId: "retry-test-2",
    config: testConfig(),
    llm: fake,
  });
  expect(res.outcome).toBe("rejected");
  expect(res.genAttempts).toBe(3);
  expect(fake.generatePrompts).toHaveLength(3);
  expect(fake.validateCalls).toBe(3);
  // 对外 reason 拼接了违规明细（判官条目 + 轮次）——落 batch_slots.error_message 供管理端展示
  const reason = res.outcome === "rejected" ? res.reason : "";
  expect(reason).toContain("校验违规 1 条（第 3/3 轮仍违规，重写已封顶）");
  expect(reason).toContain("[unverified] X");
});

test("校验一次即通过 → 单轮完成", async () => {
  const fake = new FakeLLM([null]);
  const res = await generateArticle({
    runDate: "2026-08-29",
    difficulty: "HIGH",
    threadId: "retry-test-3",
    config: testConfig(),
    llm: fake,
  });
  expect(res.outcome).toBe("success");
  expect(res.genAttempts).toBe(1);
  expect(fake.generatePrompts).toHaveLength(1);
  expect(fake.validateCalls).toBe(1);
});

/**
 * 节点级 retryPolicy 契约（`DEFAULT_NODE_RETRY_POLICY`）：LangGraph 的默认 retryOn 对
 * 带 status 且落在 no-retry 列表（400/401/402/403/404…）的错误**不重试**——402 余额不足
 * "只跑一次"正是靠这条（抛错型节点如 extractFacts/validate 也适用）。
 * 该契约是隐式的：错误一旦被包装成不带 status 的普通 Error 就退化成重试 3 次（对照组）。
 */
async function countNodeAttempts(
  errorExtras: Record<string, unknown>,
  retryPolicy: RetryPolicy,
): Promise<number> {
  const S = Annotation.Root({ n: Annotation<number> });
  let calls = 0;
  const graph = new StateGraph(S)
    .setNodeDefaults({ retryPolicy })
    .addNode("boom", async () => {
      calls++;
      throw Object.assign(new Error("402 Insufficient Balance"), errorExtras);
    })
    .addEdge(START, "boom")
    .addEdge("boom", END)
    .compile();
  await graph.invoke({ n: 0 }).catch(() => undefined); // 重试耗尽后整图抛错
  return calls;
}

test("节点级重试：错误带 status=402 → 只跑 1 次（LangGraph 默认 no-retry 列表含 402）", async () => {
  expect(await countNodeAttempts({ status: 402 }, DEFAULT_NODE_RETRY_POLICY)).toBe(1);
});

test("节点级重试：错误不带 status → 重试到 maxAttempts（对照组，钉住契约边界）", async () => {
  // 对照组只为证明"不重试"来自 status 而非策略本身：退避压到 1ms 免得白等
  const fast: RetryPolicy = { ...DEFAULT_NODE_RETRY_POLICY, initialInterval: 1, jitter: false };
  expect(await countNodeAttempts({}, fast)).toBe(DEFAULT_NODE_RETRY_POLICY.maxAttempts);
});
