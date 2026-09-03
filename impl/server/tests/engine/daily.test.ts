import { expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig } from "../../src/engine/config";
import { ensureSchema, finalizeBatch, getBatch, createBatchAndSlots, listSlots, writeSlotResult } from "../../src/engine/db";
import { generateDailyArticles, slotAttemptLog, slotThreadId } from "../../src/engine/graph/daily";
import { initLog } from "../../src/engine/graph/log";
import { localDate } from "../../src/engine/utils/time";
import { FakeLLM } from "./fake-llm";

// 每日编排真实冒烟（LOW×1 + MEDIUM×1），入库/写盘/断点全部隔离到临时目录：
// dbPath/outputDir/checkpointPath 覆写为 mkdtemp 临时目录，其余字段沿用
// loadConfig（.env 需存在）。checkpoint 隔离是必须的：threadId =
// daily-<runDate>-<slot> 为确定值，若复用 ./data/langgraph.sqlite，同日多次
// 跑同一槽位会命中共享 checkpoint（成功则复跑变毫秒级空跑 —— 测试不再真正
// 执行管线；被拒则复跑必失败），且会与生产同日 thread id 交叉污染。
// 每次运行都是真实全流程（每篇 ~3-4 次 LLM 调用 + 站点抓取），两槽并发，
// 给足 300s 超时。
test("每日生成：LOW×1 + MEDIUM×1（隔离库 + 入库断言）", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ap-daily-"));
  // 用临时库替代开发库：config 其余字段沿用 loadConfig（.env 需存在）
  // checkpointPath 一并隔离：threadId = daily-<runDate>-<slot> 为确定值，
  // 若沿用 ./data/langgraph.sqlite，同日多次跑同一槽位会命中共享 checkpoint
  // （成功则复跑变 100ms 空跑、被拒则复跑必失败），并会与生产同日 id 交叉污染。
  const cfg = {
    ...loadConfig(),
    dbPath: join(dir, "pipeline.sqlite"),
    outputDir: join(dir, "output"),
    checkpointPath: join(dir, "checkpoints.sqlite"),
  };
  const runDate = localDate(); // "今天"按系统时区（与配置一致的本地日期）
  const day = await generateDailyArticles({
    runDate,
    plan: { LOW: 1, MEDIUM: 1 },
    config: cfg,
  });

  expect(day.total).toBe(2);
  expect(day.summary.success).toBe(2);

  // 入库断言：batch_slots 全 success、articles 有 thread_id + run_date + markdown_path
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const slots = listSlots(db, runDate);
  expect(slots.map((s) => s.status)).toEqual(["success", "success"]);
  const articles = db
    .query("SELECT thread_id, title_en, run_date, markdown_path FROM articles ORDER BY id")
    .all() as { thread_id: string; title_en: string; run_date: string; markdown_path: string }[];
  expect(articles).toHaveLength(2);
  for (const row of articles) {
    expect(row.thread_id).toMatch(/^daily-/);
    expect(row.run_date).toBe(runDate);
    expect(row.markdown_path).toContain("output/");
  }
  db.close();
}, 300_000);

test("generateDailyArticles: 批次已终态(completed_with_failures) → 直接返回既有结果且不调 LLM", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ap-daily-done-"));
  const cfg = { ...loadConfig(), dbPath: join(dir, "p.sqlite"), checkpointPath: join(dir, "cp.sqlite"), outputDir: join(dir, "output") };
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" }]);
  finalizeBatch(db, b.id); // 槽位尚未写终态 → completed_with_failures
  db.close();

  const fake = new FakeLLM([null]);
  const day = await generateDailyArticles({ runDate: "2026-08-29", config: cfg, llm: fake });
  expect(fake.generatePrompts).toHaveLength(0); // LLM 一律不调
  expect(day.total).toBe(1);
  expect(day.summary).toEqual({ success: 0, rejected: 0, error: 1 }); // pending 槽位按未完成兜底
});

test("generateDailyArticles: 终态批次先落运行日志(不只 stderr)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ap-daily-donelog-"));
  const cfg = { ...loadConfig(), dbPath: join(dir, "p.sqlite"), checkpointPath: join(dir, "cp.sqlite"), outputDir: join(dir, "output") };
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" }]);
  finalizeBatch(db, b.id);
  db.close();

  const logPath = initLog(dir); // 日志落临时目录
  const day = await generateDailyArticles({ runDate: "2026-08-29", config: cfg });
  expect(day.summary).toEqual({ success: 0, rejected: 0, error: 1 });
  const content = await Bun.file(logPath).text();
  expect(content).toContain("2026-08-29 已执行结束");
});

test("generateDailyArticles: 批次 running 但槽位全终态(收口前崩溃) → 收口并返回既有结果", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ap-daily-gap-"));
  const cfg = { ...loadConfig(), dbPath: join(dir, "p.sqlite"), checkpointPath: join(dir, "cp.sqlite"), outputDir: join(dir, "output") };
  const db = new Database(cfg.dbPath);
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, [{ slotIndex: 0, difficulty: "HIGH", threadId: "daily-2026-08-29-0" }]);
  const slot = listSlots(db, "2026-08-29")[0]!;
  writeSlotResult(db, { slotId: slot.id, threadId: slot.threadId, status: "rejected" });
  // 不 finalizeBatch：模拟跑完未收口；槽位已终态 → 无 pending 可补跑
  // plan 与预置槽位一致（HIGH×1），避免默认 15 篇计划补插一批新槽位
  const fake = new FakeLLM([null]);
  const day = await generateDailyArticles({ runDate: "2026-08-29", plan: { HIGH: 1 }, config: cfg, llm: fake });
  expect(fake.generatePrompts).toHaveLength(0);
  // 收口为终态，且返回既有结果
  expect(getBatch(db, "2026-08-29")!.status).toBe("completed_with_failures");
  expect(day.summary).toEqual({ success: 0, rejected: 1, error: 0 });
  db.close();
});

test("slotThreadId: 首试与场景一递增格式", () => {
  expect(slotThreadId("2026-08-29", 3, 1)).toBe("daily-2026-08-29-3");
  expect(slotThreadId("2026-08-29", 3, 2)).toBe("daily-2026-08-29-3-2");
});

test("slotAttemptLog: 明细行包含 slot/attempt/thread/outcome 字段", () => {
  const line = slotAttemptLog("daily", {
    id: 1, batchId: 1, runDate: "2026-08-29", slotIndex: 3, difficulty: "MEDIUM",
    threadId: "daily-2026-08-29-3", status: "pending", attempts: 1, articleId: null,
  }, { attempt: 1, threadId: "daily-2026-08-29-3", outcome: "rejected", reason: "x", started: false });
  expect(line).toContain("slot 3");
  expect(line).toContain("[MEDIUM]");
  expect(line).toContain("attempt=1");
  expect(line).toContain("thread=daily-2026-08-29-3");
  expect(line).toContain("outcome=rejected");
  expect(line).toContain("reason=x");
});
