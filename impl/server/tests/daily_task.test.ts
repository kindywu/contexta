// tests/daily_task.test.ts
// 每日任务编排（启动补漏 + 定时循环 + pending 恢复 + error 补跑 + 审核行补齐）：
// genDaily/retryFailed/reRun/ensure/now/sleep 全部注入假实现——不依赖真实引擎/LLM/定时器；
// 槽位终态用真实 :memory: 库 + 引擎 listSlots 手工造，验证 runFill 的编排顺序与分派。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import {
  createBatchAndSlots,
  ensureSchema,
  finalizeBatch,
  listSlots,
  writeSlotResult,
  type SlotRow,
  type SlotStatus,
} from "../src/engine/db";
import { localDate } from "../src/engine/utils/time";
import { DailyTask, type DailyTaskCtx } from "../src/services/daily_task";
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
  const reRuns: { slot: SlotRow; seq: number }[] = [];
  const reRun = async (_ctx: DailyTaskCtx, slot: SlotRow, seq: number) => {
    reRuns.push({ slot, seq });
    events.push(`rerun:${slot.slotIndex}:${seq}`);
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

  test("error 槽存在 → reRun 恰好 1 次：传该槽 row + genSeq=1（rejected/其余不动）", async () => {
    const f = recorders();
    const { db, ctx } = makeCtx({ ...f });
    const slots = seedSlots(db, 3);
    const statuses: SlotStatus[] = ["success", "error", "rejected"];
    slots.forEach((s, i) => writeSlotResult(db, { slotId: s.id, threadId: s.threadId, status: statuses[i]! }));

    await new DailyTask(ctx).runFill(RUN_DATE);

    expect(f.reRuns).toHaveLength(1);
    expect(f.reRuns[0]!.seq).toBe(1);
    expect(f.reRuns[0]!.slot.id).toBe(slots[1]!.id);
    expect(f.reRuns[0]!.slot.slotIndex).toBe(1);
    expect(f.reRuns[0]!.slot.status).toBe("error");
    expect(f.events).toContain("ensure");
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
});

describe("daily_task startupFill", () => {
  test("同一次 now() 推导今天+明天，依次 runFill 两日", async () => {
    const fixedNow = new Date(2026, 8, 2, 10, 0, 0);
    const today = localDate(TZ, fixedNow);
    const tomorrow = localDate(TZ, new Date(fixedNow.getTime() + 86_400_000));
    const f = recorders();
    const { ctx } = makeCtx({ ...f, now: () => fixedNow });

    await new DailyTask(ctx).startupFill();

    expect(f.genCalls.map((c) => c.runDate)).toEqual([today, tomorrow]);
  });

  test("单日 fill 失败 → 另一日仍执行（失败仅记日志）", async () => {
    const fixedNow = new Date(2026, 8, 2, 10, 0, 0);
    const today = localDate(TZ, fixedNow);
    const tomorrow = localDate(TZ, new Date(fixedNow.getTime() + 86_400_000));
    const calls: string[] = [];
    const genDaily = async ({ runDate }: { runDate: string; config: AppConfig }) => {
      calls.push(runDate);
      if (runDate === today) throw new Error("今天生成失败");
    };
    const { ctx } = makeCtx({ genDaily, now: () => fixedNow });

    await expect(new DailyTask(ctx).startupFill()).resolves.toBeUndefined();
    expect(calls).toEqual([today, tomorrow]); // 今天失败不阻止明天
  });
});

describe("daily_task loop", () => {
  test("等待到 DAILY_GENERATE_HOUR:01；触发后 runFill(今天补) + runFill(明天主生成)", async () => {
    const fixedNow = new Date(2026, 8, 2, 14, 0, 0); // 14:00 ≥ 3 → 等明天 03:01
    const hour = 3; // serverCfg.dailyGenerateHour 缺省 3
    const sleeps: number[] = [];
    const stop = new Error("stop-loop");
    const sleep = async (ms: number) => {
      sleeps.push(ms);
      if (sleeps.length >= 2) throw stop; // 第一觉醒来触发一轮后终止循环
    };
    const f = recorders();
    const { ctx } = makeCtx({ ...f, now: () => fixedNow, sleep });

    await expect(new DailyTask(ctx).loop()).rejects.toThrow("stop-loop");

    // 等待毫秒 = 明天 hour:01 - now（系统时区 == 配置时区，todayStartMillis 同口径）
    const expected =
      todayStartMillis(TZ, fixedNow) + 86_400_000 + hour * 3_600_000 + 60_000 - fixedNow.getTime();
    expect(sleeps[0]).toBe(expected);

    // 触发后：今天（补）+ 明天（主生成），由同一次 now 推导
    const today = localDate(TZ, fixedNow);
    const tomorrow = localDate(TZ, new Date(fixedNow.getTime() + 86_400_000));
    expect(f.genCalls.map((c) => c.runDate)).toEqual([today, tomorrow]);
  });

  test("未到 hour 时等当天 hour:01（now 01:00 → 等今天 03:01）", async () => {
    const fixedNow = new Date(2026, 8, 2, 1, 0, 0); // 01:00 < 3 → 今天 03:01
    const hour = 3;
    const sleeps: number[] = [];
    const sleep = async (ms: number) => {
      sleeps.push(ms);
      throw new Error("stop-loop");
    };
    const { ctx } = makeCtx({ genDaily: async () => {}, retryFailed: async () => {}, now: () => fixedNow, sleep });

    await expect(new DailyTask(ctx).loop()).rejects.toThrow("stop-loop");

    const expected = todayStartMillis(TZ, fixedNow) + hour * 3_600_000 + 60_000 - fixedNow.getTime();
    expect(sleeps[0]).toBe(expected);
  });
});
