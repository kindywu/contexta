import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../../src/engine/config";
import { generateArticle } from "../../src/engine/graph";
import { shouldRetryValidate } from "../../src/engine/graph/graph";
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
