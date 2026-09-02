import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Database } from "bun:sqlite";
import { loadConfig } from "../../src/engine/config";
import {
  classifySlot,
  retryFailedSlots,
  slotThreadId,
} from "../../src/engine/graph/daily";
import { generateArticle } from "../../src/engine/graph";
import {
  ensureSchema, finalizeBatch, createBatchAndSlots, listSlots, writeSlotResult,
} from "../../src/engine/db";
import { FakeLLM } from "./fake-llm";

/** retry CLI 只解决程序崩溃导致的中断（langgraph 特性），不做业务刷重试。 */

test("classifySlot: pending + 无终态 checkpoint → resume（同线程续跑）", () => {
  expect(classifySlot({ status: "pending", checkpointOutcome: undefined, runDate: "2026-08-29", slot: 1 })).toBe("resume");
});

test("classifySlot: pending + 终态 checkpoint（崩溃间隙）→ sync（同步终态，不重跑）", () => {
  expect(classifySlot({ status: "pending", checkpointOutcome: "rejected", runDate: "2026-08-29", slot: 3 })).toBe("sync");
  expect(classifySlot({ status: "pending", checkpointOutcome: "success", runDate: "2026-08-29", slot: 4 })).toBe("sync");
});

test("classifySlot: error/rejected 是业务终态，retry 不处理 → skip", () => {
  expect(classifySlot({ status: "error", checkpointOutcome: undefined, runDate: "2026-08-29", slot: 3 })).toBe("skip");
  expect(classifySlot({ status: "rejected", checkpointOutcome: undefined, runDate: "2026-08-29", slot: 5 })).toBe("skip");
});

/** 隔离配置：db/checkpoint/output 全走临时目录。 */
function isolatedConfig() {
  const dir = mkdtempSync(join(tmpdir(), "ap-retry-"));
  return {
    ...loadConfig(),
    dbPath: join(dir, "p.sqlite"),
    checkpointPath: join(dir, "cp.sqlite"),
    outputDir: join(dir, "output"),
  };
}

test("retryFailedSlots: pending + 终态 rejected checkpoint → 同步终态，不重跑、不调 LLM", async () => {
  const cfg = isolatedConfig();
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const threadId = slotThreadId("2026-08-29", 0, 1);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "HIGH", threadId }]);

  // 先让 threadId 的图跑出「终态 rejected」checkpoint（3 轮违规），但不落库
  const fake = new FakeLLM([
    [{ ruleId: "unverified", message: "X" }],
    [{ ruleId: "unverified", message: "X" }],
    [{ ruleId: "unverified", message: "X" }],
  ]);
  await generateArticle({ runDate: "2026-08-29", difficulty: "HIGH", threadId, config: cfg, llm: fake });
  const genBefore = fake.generatePrompts.length;
  const valBefore = fake.validateCalls;

  const result = await retryFailedSlots({ runDate: "2026-08-29", config: cfg, llm: fake });
  expect(result).toEqual({ runDate: "2026-08-29", resumed: 0, synced: 1, stillFailed: 1, note: null });
  // 只同步终态，没有再发生任何 LLM 调用
  expect(fake.generatePrompts.length).toBe(genBefore);
  expect(fake.validateCalls).toBe(valBefore);
  // 槽位写回 rejected，且 attempts 记录图内实际轮数（3 轮含首试）
  const slot = listSlots(db, "2026-08-29")[0]!;
  expect(slot.status).toBe("rejected");
  expect(slot.attempts).toBe(3);
  db.close();
});

test("retryFailedSlots: pending + 终态 success checkpoint → 同步成功（写 md+入库，不重跑）", async () => {
  const cfg = isolatedConfig();
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const threadId = slotThreadId("2026-08-29", 0, 1);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "HIGH", threadId }]);

  // 图跑成功（checkpoint 终态 success），但 DB 没落
  const fake = new FakeLLM([null]);
  await generateArticle({ runDate: "2026-08-29", difficulty: "HIGH", threadId, config: cfg, llm: fake });
  const genBefore = fake.generatePrompts.length;

  const result = await retryFailedSlots({ runDate: "2026-08-29", config: cfg, llm: fake });
  expect(result).toEqual({ runDate: "2026-08-29", resumed: 0, synced: 1, stillFailed: 0, note: null });
  expect(fake.generatePrompts.length).toBe(genBefore);
  const slot = listSlots(db, "2026-08-29")[0]!;
  expect(slot.status).toBe("success");
  // 文章与 markdown 已补齐
  const articles = db.query("SELECT article_id, title_en FROM batch_slots s JOIN articles a ON a.id = s.article_id WHERE s.slot_index = 0").all() as { article_id: number; title_en: string }[];
  expect(articles).toHaveLength(1);
  expect(articles[0]!.title_en).toBe("Draft 1");
  db.close();
});

test("retryFailedSlots: pending 无 checkpoint → resume 续跑（照常生成到终态）", async () => {
  const cfg = isolatedConfig();
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "HIGH", threadId: slotThreadId("2026-08-29", 0, 1) }]);

  const fake = new FakeLLM([null]);
  const result = await retryFailedSlots({ runDate: "2026-08-29", config: cfg, llm: fake });
  expect(result).toEqual({ runDate: "2026-08-29", resumed: 1, synced: 0, stillFailed: 0, note: null });
  expect(fake.generatePrompts).toHaveLength(1);
  expect(listSlots(db, "2026-08-29")[0]!.status).toBe("success");
  db.close();
});

test("retryFailedSlots: 无失败槽位 → 全部 0 且批次收口（不调 LLM）", async () => {
  const cfg = isolatedConfig();
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "LOW", threadId: slotThreadId("2026-08-29", 0, 1) }]);
  writeSlotResult(db, { slotId: listSlots(db, "2026-08-29")[0]!.id, threadId: slotThreadId("2026-08-29", 0, 1), status: "success", articleId: 1 });

  const result = await retryFailedSlots({ runDate: "2026-08-29", config: cfg });
  expect({ runDate: result.runDate, resumed: result.resumed, synced: result.synced, stillFailed: result.stillFailed })
    .toEqual({ runDate: "2026-08-29", resumed: 0, synced: 0, stillFailed: 0 });
  // 空跑也要给出具体提示（流程已正常结束）
  expect(typeof result.note).toBe("string");
  expect(result.note).toContain("正常结束");

  // 批次被收口
  expect(
    (db.query("SELECT status FROM article_batches WHERE run_date = ?").get("2026-08-29") as { status: string }).status,
  ).toBe("completed");
  db.close();
});

test("retryFailedSlots: 批次不存在 → 全零结果并提示无执行记录", async () => {
  const cfg = isolatedConfig();
  const result = await retryFailedSlots({ runDate: "2026-08-30", config: cfg });
  expect({ runDate: result.runDate, resumed: result.resumed, synced: result.synced, stillFailed: result.stillFailed })
    .toEqual({ runDate: "2026-08-30", resumed: 0, synced: 0, stillFailed: 0 });
  expect(typeof result.note).toBe("string");
  expect(result.note).toContain("无执行记录");
});

test("retryFailedSlots: 批次已终态但含业务终态槽位(今天 13/15 的场景) → 空跑并提示业务终态", async () => {
  const cfg = isolatedConfig();
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "HIGH", threadId: "daily-2026-08-29-0" }]);
  const slot = listSlots(db, "2026-08-29")[0]!;
  writeSlotResult(db, { slotId: slot.id, threadId: slot.threadId, status: "rejected" });
  finalizeBatch(db, b.id); // completed_with_failures：流程正常结束，无 pending

  const fake = new FakeLLM([null]); // 不应当被调用
  const result = await retryFailedSlots({ runDate: "2026-08-29", config: cfg, llm: fake });
  expect({ runDate: result.runDate, resumed: result.resumed, synced: result.synced, stillFailed: result.stillFailed })
    .toEqual({ runDate: "2026-08-29", resumed: 0, synced: 0, stillFailed: 1 });
  expect(typeof result.note).toBe("string");
  expect(result.note).toContain("正常结束");
  expect(result.note).toContain("业务终态");
  expect(fake.generatePrompts).toHaveLength(0);
  db.close();
});

test("slotThreadId: 首试与增量线程格式（保留旧语义）", () => {
  expect(slotThreadId("2026-08-29", 3, 1)).toBe("daily-2026-08-29-3");
  expect(slotThreadId("2026-08-29", 3, 2)).toBe("daily-2026-08-29-3-2");
});
