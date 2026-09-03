// tests/daily_task.test.ts
// 每日任务编排（窗口触发 + pending 恢复 + error 补跑 + 审核行补齐）：
// genDaily/retryFailed/ensure/now/sleep 注入假实现——不依赖真实引擎/LLM/定时器；
// 槽位终态用真实 :memory: 库 + 引擎 listSlots 手工造，验证 runFill 的编排顺序与分派。
// 唯一例外：error 补跑唯一 genSeq 测试用真实 retrySlot（缺省 reRun）+ 注入 gen（error 三态）。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import type { ArticleResult } from "../src/engine/graph/state";
import {
  createBatchAndSlots,
  ensureSchema,
  finalizeBatch,
  listSlots,
  writeSlotResult,
  type SlotRow,
  type SlotStatus,
} from "../src/engine/db";
import type { GenArgs } from "../src/services/review_service";
import {
  DailyTask,
  isInDailyWindow,
  nextTriggerWaitMs,
  type DailyTaskCtx,
} from "../src/services/daily_task";
import { todayStartMillis } from "../src/time";

const RUN_DATE = "2026-09-02";
const TZ = "Asia/Shanghai";

/** 造一个完整上下文（真实 :memory: 库 + 引擎表 + 服务端表；seam 全部可覆写）。 */
function makeCtx(overrides: Partial<DailyTaskCtx> = {}) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  const serverCfg = loadServerConfig({
    JWT_SECRET: "s".repeat(32),
    LLM_API_KEY: "k",
    TIMEZONE: TZ,
  });
  const engineCfg: AppConfig = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "dt-cp.sqlite"),
    outputDir: join(tmpdir(), "dt-out"),
  };
  const ctx: DailyTaskCtx = { db, engineCfg, serverCfg, ...overrides };
  return { db, serverCfg, engineCfg, ctx };
}

/** 记录型假实现集合：events 按调用顺序记录，便于断言编排顺序。 */
function recorders() {
  const events: string[] = [];
  const genCalls: { runDate: string; config: AppConfig }[] = [];
  const genDaily = async (args: { runDate: string; config: AppConfig }) => {
    genCalls.push(args);
    events.push(`gen:${args.runDate}`);
  };
  const retryFailed = async (args: { runDate: string; config: AppConfig }) => {
    events.push(`retry:${args.runDate}`);
  };
  const reRuns: { slot: SlotRow }[] = [];
  const reRun = async (_ctx: DailyTaskCtx, slot: SlotRow) => {
    reRuns.push({ slot });
    events.push(`rerun:${slot.slotIndex}`);
  };
  const ensure = (_db: Database) => {
    events.push("ensure");
    return 0;
  };
  return { events, genCalls, genDaily, retryFailed, reRuns, reRun, ensure };
}

/** 造一批槽位（默认全 pending），返回槽位行。 */
function seedSlots(db: Database, total: number): SlotRow[] {
  const batch = createBatchAndSlots(
    db,
    RUN_DATE,
    total,
    Array.from({ length: total }, (_, i) => ({
      slotIndex: i,
      difficulty: (i % 2 === 0 ? "LOW" : "MEDIUM") as "LOW" | "MEDIUM",
      threadId: `daily-${RUN_DATE}-${i}`,
    })),
  );
  return listSlots(db, RUN_DATE).map((s) => ({ ...s, batchId: batch.id }));
}

describe("daily_task runFill", () => {
  test("无批次日期 → genDaily/retryFailed/ensure 依次被调（runDate + config 正确）", async () => {
    const f = recorders();
    const { engineCfg, ctx } = makeCtx({ ...f });
    await new DailyTask(ctx).runFill(RUN_DATE);

    expect(f.events).toEqual([`gen:${RUN_DATE}`, `retry:${RUN_DATE}`, "ensure"]);
    expect(f.genCalls).toHaveLength(1);
    expect(f.genCalls[0]!.runDate).toBe(RUN_DATE);
    expect(f.genCalls[0]!.config).toBe(engineCfg); // 引擎 seam 收到 engineCfg
    expect(f.reRuns).toHaveLength(0); // 无 error 槽 → 不补跑
  });

  test("槽位全 success 且批次已收口 → 顺序 gen→retry→(无 error 补跑)→ensure", async () => {
    const f = recorders();
    const { db, ctx } = makeCtx({ ...f });
    const slots = seedSlots(db, 3);
    for (const s of slots) {
      writeSlotResult(db, { slotId: s.id, threadId: s.threadId, status: "success" });
    }
    finalizeBatch(db, slots[0]!.batchId);

    await new DailyTask(ctx).runFill(RUN_DATE);

    expect(f.events).toEqual([`gen:${RUN_DATE}`, `retry:${RUN_DATE}`, "ensure"]);
    expect(f.reRuns).toHaveLength(0); // 无 error 槽
  });

  test("error 槽存在 → reRun 恰好 1 次：传该槽 row（rejected/其余不动）", async () => {
    const f = recorders();
    const { db, ctx } = makeCtx({ ...f });
    const slots = seedSlots(db, 3);
    const statuses: SlotStatus[] = ["success", "error", "rejected"];
    slots.forEach((s, i) => writeSlotResult(db, { slotId: s.id, threadId: s.threadId, status: statuses[i]! }));

    await new DailyTask(ctx).runFill(RUN_DATE);

    expect(f.reRuns).toHaveLength(1);
    expect(f.reRuns[0]!.slot.id).toBe(slots[1]!.id);
    expect(f.reRuns[0]!.slot.slotIndex).toBe(1);
    expect(f.reRuns[0]!.slot.status).toBe("error");
    expect(f.events).toContain("ensure");
  });

  test("error 槽补跑走 retrySlot 唯一 genSeq：槽位两次 runFill 均真尝试且 threadId 不同", async () => {
    // 不注入 reRun（走缺省 = retrySlot 闭包）+ 注入 gen（error 三态，不真调引擎/LLM）：
    // 槽位两次都留 error → 第二次 runFill 仍进入补跑；genSeq = Date.now() 唯一
    // （pre-fix reRunSlot(ctx, slot, 1) 恒 -r1，两次同 id——命中引擎"同 threadId
    // 终态 checkpoint 复用"契约时第二次静默 no-op）。
    const genCalls: string[] = [];
    const gen = async (args: GenArgs): Promise<ArticleResult> => {
      genCalls.push(args.threadId);
      await new Promise((r) => setTimeout(r, 5)); // 两次 Date.now() 落不同毫秒
      return { outcome: "error", message: "仍失败" };
    };
    const { db, ctx } = makeCtx({
      genDaily: async () => {},
      retryFailed: async () => {},
      gen,
    });
    const slots = seedSlots(db, 1);
    writeSlotResult(db, { slotId: slots[0]!.id, threadId: slots[0]!.threadId, status: "error" });

    const task = new DailyTask(ctx);
    await task.runFill(RUN_DATE);
    const t1 = listSlots(db, RUN_DATE)[0]!.threadId;
    await task.runFill(RUN_DATE);
    const t2 = listSlots(db, RUN_DATE)[0]!.threadId;

    expect(genCalls).toHaveLength(2); // 两次都真尝试（非 checkpoint 空跑）
    expect(t1).toMatch(/^daily-2026-09-02-0-r\d+$/);
    expect(t2).toMatch(/^daily-2026-09-02-0-r\d+$/);
    expect(t2).not.toBe(t1); // R4 唯一 genSeq：第二次不复用同 id
  });

  test("genDaily 抛错 → 不中断：retryFailed/ensure 仍被调，runFill 不抛", async () => {
    const f = recorders();
    const genDaily = async () => {
      throw new Error("LLM 网关挂了");
    };
    const { ctx } = makeCtx({ genDaily, retryFailed: f.retryFailed, reRun: f.reRun, ensure: f.ensure });

    await expect(new DailyTask(ctx).runFill(RUN_DATE)).resolves.toBeUndefined();
    expect(f.events).toEqual(["retry:2026-09-02", "ensure"]);
  });

  test("error 槽 reRun 抛错 → 留 error 不中断，ensure 仍被调", async () => {
    const f = recorders();
    const reRun = async () => {
      throw new Error("补跑 IO 失败");
    };
    const { db, ctx } = makeCtx({ genDaily: f.genDaily, retryFailed: f.retryFailed, reRun, ensure: f.ensure });
    const slots = seedSlots(db, 2);
    writeSlotResult(db, { slotId: slots[0]!.id, threadId: slots[0]!.threadId, status: "success" });
    writeSlotResult(db, { slotId: slots[1]!.id, threadId: slots[1]!.threadId, status: "error" });

    await expect(new DailyTask(ctx).runFill(RUN_DATE)).resolves.toBeUndefined();
    expect(f.events).toContain("ensure"); // 补跑失败不阻断收尾
    const after = listSlots(db, RUN_DATE);
    expect(after[1]!.status).toBe("error"); // 补跑仍失败 → 留 error
  });

  test("同日并发 runFill → in-flight 去重：内层 genDaily 只被调 1 次（不双跑）", async () => {
    // genDaily 挂起至测试释放：第二次 runFill 时第一次仍在跑——去重必须返回同一
    // Promise 而非再跑一轮（双跑 = 双倍 LLM 成本 + 并发写同槽位）。
    const genCalls: string[] = [];
    let release: () => void = () => {};
    const gate = new Promise<void>((r) => (release = r));
    const genDaily = async (args: { runDate: string; config: AppConfig }) => {
      genCalls.push(args.runDate);
      await gate;
    };
    const { ctx } = makeCtx({ genDaily, retryFailed: async () => {}, ensure: () => 0 });
    const task = new DailyTask(ctx);

    const p1 = task.runFill(RUN_DATE);
    const p2 = task.runFill(RUN_DATE);
    expect(genCalls).toEqual([RUN_DATE]); // 第二次调用未触发新生成
    expect(p2).toBe(p1); // 同一 in-flight Promise

    release();
    await Promise.all([p1, p2]);
    expect(genCalls).toHaveLength(1); // 全程只生成一次
  });
});

describe("daily_task 窗口判定", () => {
  const W = { start: 480, end: 495 }; // 08:00-08:15

  test("isInDailyWindow：窗口内（含边界）true，窗口外 false", () => {
    expect(isInDailyWindow(new Date(2026, 8, 2, 8, 0, 0), W, TZ)).toBe(true);
    expect(isInDailyWindow(new Date(2026, 8, 2, 8, 10, 0), W, TZ)).toBe(true);
    expect(isInDailyWindow(new Date(2026, 8, 2, 8, 15, 0), W, TZ)).toBe(true);
    expect(isInDailyWindow(new Date(2026, 8, 2, 7, 59, 59), W, TZ)).toBe(false);
    expect(isInDailyWindow(new Date(2026, 8, 2, 8, 15, 1), W, TZ)).toBe(false);
    expect(isInDailyWindow(new Date(2026, 8, 2, 20, 0, 0), W, TZ)).toBe(false);
  });

  test("nextTriggerWaitMs：未到窗口 → 今日窗口开始；窗口内/已过 → 明日窗口开始", () => {
    const at = (h: number, m: number, s = 0) => new Date(2026, 8, 2, h, m, s);
    const start = todayStartMillis(TZ, at(0, 0)); // 2026-09-02 本地零点
    expect(nextTriggerWaitMs(at(7, 0), W, TZ)).toBe(480 * 60_000 - 7 * 3_600_000); // 08:00-07:00 = 1h
    expect(nextTriggerWaitMs(at(8, 10), W, TZ)).toBe(start + 480 * 60_000 + 86_400_000 - at(8, 10).getTime());
    expect(nextTriggerWaitMs(at(8, 20), W, TZ)).toBe(start + 480 * 60_000 + 86_400_000 - at(8, 20).getTime());
  });
});

describe("daily_task loop（窗口触发 + 三态判定）", () => {
  const W = { start: 480, end: 495 }; // 08:00-08:15

  // fake sleep：记录等待毫秒后立即抛错终止循环（每次触发点的等待就是断言目标）
  function stopLoopSleep(sleeps: number[]) {
    return async (msValue: number) => {
      sleeps.push(msValue);
      throw new Error("stop-loop");
    };
  }

  test("窗口内（08:10）→ 立即触发，只生成当天一天，随后睡到明日窗口", async () => {
    const fixedNow = new Date(2026, 8, 2, 8, 10, 0);
    const sleeps: number[] = [];
    const f = recorders();
    const { ctx } = makeCtx({ ...f, now: () => fixedNow, sleep: stopLoopSleep(sleeps) });

    await expect(new DailyTask(ctx).loop()).rejects.toThrow("stop-loop");

    // 只生成触发时刻当天（2026-09-02），不再今日补跑 + 明日主生成双跑
    expect(f.genCalls.map((c) => c.runDate)).toEqual([RUN_DATE]);
    // 处理后睡到明日窗口开始 = 今日零点 + 480min + 24h - 08:10
    const dayStart = todayStartMillis(TZ, fixedNow);
    expect(sleeps[0]).toBe(dayStart + 480 * 60_000 + 86_400_000 - fixedNow.getTime());
  });

  test("未到窗口（07:00）→ 先睡到今日窗口开始，不触发生成", async () => {
    const fixedNow = new Date(2026, 8, 2, 7, 0, 0);
    const sleeps: number[] = [];
    const f = recorders();
    const { ctx } = makeCtx({ ...f, now: () => fixedNow, sleep: stopLoopSleep(sleeps) });

    await expect(new DailyTask(ctx).loop()).rejects.toThrow("stop-loop");
    expect(sleeps[0]).toBe(3_600_000); // 08:00 - 07:00
    expect(f.genCalls).toHaveLength(0);
  });

  test("已过窗口（08:20）→ 跳过当天，睡到明日窗口（错过不补、不重试）", async () => {
    const fixedNow = new Date(2026, 8, 2, 8, 20, 0);
    const sleeps: number[] = [];
    const f = recorders();
    const { ctx } = makeCtx({ ...f, now: () => fixedNow, sleep: stopLoopSleep(sleeps) });

    await expect(new DailyTask(ctx).loop()).rejects.toThrow("stop-loop");
    expect(sleeps[0]).toBe(480 * 60_000 + 86_400_000 - 8 * 3_600_000 - 20 * 60_000); // 明日 08:00
    expect(f.genCalls).toHaveLength(0); // 当天已错过 → 不生成
  });

  test("当天批次已收口（全 success）→ 跳过，不调 runFill", async () => {
    const fixedNow = new Date(2026, 8, 2, 8, 10, 0);
    const sleeps: number[] = [];
    const f = recorders();
    const { db, ctx } = makeCtx({ ...f, now: () => fixedNow, sleep: stopLoopSleep(sleeps) });
    const slots = seedSlots(db, 3);
    for (const s of slots) writeSlotResult(db, { slotId: s.id, threadId: s.threadId, status: "success" });
    finalizeBatch(db, slots[0]!.batchId); // status = completed

    await expect(new DailyTask(ctx).loop()).rejects.toThrow("stop-loop");
    expect(f.genCalls).toHaveLength(0); // 已生成成功 → 跳过
    expect(f.events).toEqual([]); // runFill 完全未调用
  });

  test("自定义窗口生效（12:00-12:30）：08:10 不在窗口 → 睡到 12:00；12:10 在窗口 → 触发", async () => {
    const custom = loadServerConfig({
      JWT_SECRET: "s".repeat(32),
      LLM_API_KEY: "k",
      TIMEZONE: TZ,
      DAILY_GENERATE_WINDOW: "12:00-12:30",
    });
    // 12:10 触发当天
    const f = recorders();
    const sleeps: number[] = [];
    const inNow = new Date(2026, 8, 2, 12, 10, 0);
    const { ctx: c1 } = makeCtx({
      ...f,
      serverCfg: custom,
      now: () => inNow,
      sleep: stopLoopSleep(sleeps),
    });
    await expect(new DailyTask(c1).loop()).rejects.toThrow("stop-loop");
    expect(f.genCalls.map((c) => c.runDate)).toEqual([RUN_DATE]);

    // 08:10 未到窗口 → 睡到 12:00
    const g = recorders();
    const sleeps2: number[] = [];
    const { ctx: c2 } = makeCtx({
      ...g,
      serverCfg: custom,
      now: () => new Date(2026, 8, 2, 8, 10, 0),
      sleep: stopLoopSleep(sleeps2),
    });
    await expect(new DailyTask(c2).loop()).rejects.toThrow("stop-loop");
    expect(sleeps2[0]).toBe(12 * 3_600_000 - 8 * 3_600_000 - 10 * 60_000); // 3h50m
    expect(g.genCalls).toHaveLength(0);
  });
});
