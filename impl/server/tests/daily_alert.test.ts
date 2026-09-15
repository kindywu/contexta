// 未收口看门狗（"有开始没结束"的自动判定）：
// 每日窗口结束 + 60 分钟后检查当天批次——不存在 / 仍 running → 告警；已收口 → 静默；按日去重。
// now/sleep/notify 全注入：不依赖真实时钟，也不需要生成循环活着（这正是它能发现卡死的前提）。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import { createBatchAndSlots, ensureSchema, finalizeBatch, listSlots, writeSlotResult } from "../src/engine/db";
import type { DailyAlertArgs } from "../src/services/feishu_notify";
import { localDate } from "../src/engine/utils/time";
import { alertAtMillis, ALERT_GRACE_MINUTES, DailyAlertWatchdog, type DailyAlertCtx } from "../src/services/daily_alert";
import { todayStartMillis } from "../src/time";

// 时间口径说明：todayStartMillis 以【系统时区】构造当地零点（生产由启动硬闸保证
// 系统时区 == 配置时区，见 src/time.ts），而 `bun test` 以 TZ=UTC 运行——因此本文件的
// 时刻断言一律相对 todayStartMillis 推导（与 tests/daily_task.test.ts 同法），
// 不写死绝对时刻：既验证逻辑，又不依赖运行环境时区。
const TZ = "Asia/Shanghai";
const WINDOW_END = 8 * 60 + 15; // 08:15 窗口结束
const ALERT_OFFSET_MS = (WINDOW_END + ALERT_GRACE_MINUTES) * 60_000; // → 09:15
const DAY_START = todayStartMillis(TZ, new Date("2026-09-16T02:00:00Z"));
const RUN_DATE = localDate(TZ, new Date(DAY_START + ALERT_OFFSET_MS));
/** 检查点（配置时区 09:15）。 */
const CHECK_AT = new Date(DAY_START + ALERT_OFFSET_MS);
/** 窗口内的时刻（08:00）——检查点之前。 */
const BEFORE_AT = new Date(DAY_START + 8 * 3_600_000);
/** 检查点之后 45 分钟（10:00）——用于"已过点立即检查"。 */
const AFTER_AT = new Date(CHECK_AT.getTime() + 45 * 60_000);

function makeCtx(overrides: Partial<DailyAlertCtx> = {}) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  const alerts: DailyAlertArgs[] = [];
  const engineCfg: AppConfig = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "da-cp.sqlite"),
    outputDir: join(tmpdir(), "da-out"),
  };
  const ctx: DailyAlertCtx = {
    db,
    serverCfg: loadServerConfig({
      JWT_SECRET: "s".repeat(32),
      ADMIN_JWT_SECRET: "a".repeat(32),
      LLM_API_KEY: "k",
      TIMEZONE: TZ,
    }),
    engineCfg,
    notified: new Set<string>(),
    notify: async (_ctx, args) => {
      alerts.push(args);
    },
    ...overrides,
  };
  return { db, ctx, alerts };
}

/** 造假批次并收口（或保持 running）。 */
function seed(db: Database, close: boolean): void {
  const batch = createBatchAndSlots(db, RUN_DATE, 1, [
    { slotIndex: 0, difficulty: "LOW", threadId: `daily-${RUN_DATE}-0` },
  ]);
  const slot = listSlots(db, RUN_DATE)[0]!;
  writeSlotResult(db, { slotId: slot.id, threadId: slot.threadId, status: "success" });
  if (close) finalizeBatch(db, batch.id);
}

describe("alertAtMillis（检查时刻 = 窗口结束 + 60 分钟）", () => {
  test("= 当天零点 + 窗口结束 + 宽限期（宽限期为 60 分钟）", () => {
    const now = new Date("2026-09-16T02:00:00Z");
    expect(ALERT_GRACE_MINUTES).toBe(60);
    expect(alertAtMillis(now, WINDOW_END, TZ) - todayStartMillis(TZ, now)).toBe(ALERT_OFFSET_MS);
    // 宽限期确实被计入（改宽限期 → 检查点跟着推后）
    expect(alertAtMillis(now, WINDOW_END + 30, TZ) - alertAtMillis(now, WINDOW_END, TZ)).toBe(30 * 60_000);
  });
});

describe("checkOnce（一次检查）", () => {
  test("未到检查点 → 不检查、不告警", async () => {
    const { ctx, alerts } = makeCtx();
    const done = await new DailyAlertWatchdog(ctx).checkOnce(BEFORE_AT);
    expect(done).toBe(false);
    expect(alerts).toHaveLength(0);
  });
  test("到点 + 当天无批次 → 告警（batchStatus=none）", async () => {
    const { ctx, alerts } = makeCtx();
    const done = await new DailyAlertWatchdog(ctx).checkOnce(CHECK_AT);
    expect(done).toBe(true);
    expect(alerts).toEqual([{ runDate: RUN_DATE, checkedAt: CHECK_AT, batchStatus: "none" }]);
  });
  test("到点 + 批次仍 running → 告警", async () => {
    const { db, ctx, alerts } = makeCtx();
    seed(db, false);
    expect(await new DailyAlertWatchdog(ctx).checkOnce(CHECK_AT)).toBe(true);
    expect(alerts[0]!.batchStatus).toBe("running");
  });
  test("到点但批次已收口 → 静默（正常完成不告警）", async () => {
    const { db, ctx, alerts } = makeCtx();
    seed(db, true);
    expect(await new DailyAlertWatchdog(ctx).checkOnce(CHECK_AT)).toBe(false);
    expect(alerts).toHaveLength(0);
  });
  test("同日重复检查 → 只告警一次（按日去重）", async () => {
    const { ctx, alerts } = makeCtx();
    const wd = new DailyAlertWatchdog(ctx);
    await wd.checkOnce(CHECK_AT);
    expect(await wd.checkOnce(AFTER_AT)).toBe(false);
    expect(alerts).toHaveLength(1);
  });
});

describe("loop（睡眠到检查点）", () => {
  test("未到检查点（07:00）→ 先睡到 09:15，不检查", async () => {
    const sleeps: number[] = [];
    const now = BEFORE_AT;
    const { ctx, alerts } = makeCtx({
      now: () => now,
      sleep: async (ms) => {
        sleeps.push(ms);
        throw new Error("stop-loop");
      },
    });
    await expect(new DailyAlertWatchdog(ctx).loop()).rejects.toThrow("stop-loop");
    expect(sleeps[0]).toBe(CHECK_AT.getTime() - now.getTime());
    expect(alerts).toHaveLength(0);
  });
  test("告警 seam 抛错 → 看门狗不死，仍睡到明日检查点", async () => {
    const sleeps: number[] = [];
    const now = AFTER_AT;
    const { ctx } = makeCtx({
      now: () => now,
      notify: async () => {
        throw new Error("feishu down");
      },
      sleep: async (ms) => {
        sleeps.push(ms);
        throw new Error("stop-loop");
      },
    });
    await expect(new DailyAlertWatchdog(ctx).loop()).rejects.toThrow("stop-loop");
    expect(sleeps).toHaveLength(1);
  });
  test("已过检查点 → 立即检查一次，然后睡到明日检查点", async () => {
    const sleeps: number[] = [];
    const now = AFTER_AT;
    const { ctx, alerts } = makeCtx({
      now: () => now,
      sleep: async (ms) => {
        sleeps.push(ms);
        throw new Error("stop-loop");
      },
    });
    await expect(new DailyAlertWatchdog(ctx).loop()).rejects.toThrow("stop-loop");
    expect(alerts).toHaveLength(1); // 当天无批次 → 立即告警
    // 睡到明日检查点
    expect(sleeps[0]).toBe(CHECK_AT.getTime() + 86_400_000 - now.getTime());
  });
});
