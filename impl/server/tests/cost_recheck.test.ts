// 成本复核（结束卡成本为 0 → 10 分钟后重查余额 → 发复核卡）：
// sleep/probe/notify 全注入假实现——不真等 10 分钟、不真查余额、不真发飞书；
// 重点锁定"延迟时长、入参口径、非抛纪律"三条。
import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import { ensureSchema } from "../src/engine/db";
import {
  isZeroCost,
  RECHECK_DELAY_MS,
  recheckCost,
  type CostRecheckArgs,
  type CostRecheckCtx,
} from "../src/services/cost_recheck";
import type { DailyRecheckArgs } from "../src/services/feishu_notify";
import type { BalanceSnapshot } from "../src/services/llm_balance";

const TZ = "Asia/Shanghai";
const RUN_DATE = "2026-09-17";
const FIXED = new Date("2026-09-17T00:10:00Z");
/** 复核时刻（结束卡后 10 分钟）。 */
const CHECKED = new Date("2026-09-17T00:20:00Z");

const snap = (total: number, currency = "CNY"): BalanceSnapshot => ({ currency, total, at: FIXED });

/** ctx：seam 全为记录型假实现；probe 固定返回 settled。 */
function makeCtx(settled: BalanceSnapshot | null, overrides: Partial<CostRecheckCtx> = {}) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  const events: string[] = [];
  const notified: DailyRecheckArgs[] = [];
  const engineCfg: AppConfig = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "cr-cp.sqlite"),
    outputDir: join(tmpdir(), "cr-out"),
  };
  const ctx: CostRecheckCtx = {
    db,
    serverCfg: loadServerConfig({
      JWT_SECRET: "s".repeat(32),
      ADMIN_JWT_SECRET: "a".repeat(32),
      LLM_API_KEY: "k",
      TIMEZONE: TZ,
    }),
    engineCfg,
    balance: { baseUrl: "https://api.deepseek.com", apiKey: "k" },
    now: () => CHECKED,
    sleep: async (ms) => {
      events.push(`sleep:${ms}`);
    },
    probe: async () => {
      events.push("probe");
      return settled;
    },
    notify: async (_c, a) => {
      events.push("notify");
      notified.push(a);
    },
    ...overrides,
  };
  return { ctx, events, notified };
}

const recheckArgs = (): CostRecheckArgs => ({
  runDate: RUN_DATE,
  balanceBefore: snap(3.23),
  balanceAfter: snap(3.23),
});

describe("isZeroCost（成本为 0 判定）", () => {
  test("两侧余额都查到且相等 → 视为成本 0", () => {
    expect(isZeroCost(snap(3.23), snap(3.23))).toBe(true);
    expect(isZeroCost(snap(0), snap(0))).toBe(true);
  });
  test("下降（已结算）/ 上升（充值）→ 不算 0", () => {
    expect(isZeroCost(snap(3.65), snap(3.23))).toBe(false);
    expect(isZeroCost(snap(3.23), snap(13.23))).toBe(false);
  });
  test("任一未知（查询失败）→ 不算 0（不误排复核）", () => {
    expect(isZeroCost(null, snap(3.23))).toBe(false);
    expect(isZeroCost(snap(3.23), null)).toBe(false);
    expect(isZeroCost(null, null)).toBe(false);
  });
});

describe("recheckCost（延迟复核编排）", () => {
  test("睡 10 分钟 → 查余额 → 发复核卡：入参带结束卡两侧余额与复核快照", async () => {
    const { ctx, events, notified } = makeCtx(snap(2.81));
    await recheckCost(ctx, recheckArgs());

    expect(RECHECK_DELAY_MS).toBe(600_000);
    expect(events).toEqual([`sleep:${RECHECK_DELAY_MS}`, "probe", "notify"]);
    expect(notified).toHaveLength(1);
    const a = notified[0]!;
    expect(a.runDate).toBe(RUN_DATE);
    expect(a.balanceBefore.total).toBe(3.23);
    expect(a.balanceAfter.total).toBe(3.23);
    expect(a.balanceSettled!.total).toBe(2.81);
    expect(a.checkedAt).toEqual(CHECKED);
  });

  test("复核余额查询失败（null）→ 照发复核通知（如实标注未知）", async () => {
    const { ctx, notified } = makeCtx(null);
    await recheckCost(ctx, recheckArgs());
    expect(notified).toHaveLength(1);
    expect(notified[0]!.balanceSettled).toBeNull();
  });

  test("sleep 抛错 → 不抛、不查余额、不发通知（复核故障绝不外溢）", async () => {
    const { ctx, events, notified } = makeCtx(snap(2.81), {
      sleep: async () => {
        throw new Error("timer down");
      },
    });
    await expect(recheckCost(ctx, recheckArgs())).resolves.toBeUndefined();
    expect(events).toEqual([]);
    expect(notified).toHaveLength(0);
  });

  test("probe/notify 抛错 → 不抛（fire-and-forget 链不得炸）", async () => {
    const boom = async () => {
      throw new Error("boom");
    };
    const { ctx: c1 } = makeCtx(null, { probe: boom });
    await expect(recheckCost(c1, recheckArgs())).resolves.toBeUndefined();

    const { ctx: c2, notified } = makeCtx(null, { notify: boom });
    await expect(recheckCost(c2, recheckArgs())).resolves.toBeUndefined();
    expect(notified).toHaveLength(0);
  });
});
