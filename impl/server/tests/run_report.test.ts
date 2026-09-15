// 每日运行上报包装（查余额 → 开始卡 → 跑 → 查余额 → 结束卡；抛错也发再重抛）：
// probe/notifyStart/notifyEnd 全部注入记录型假实现——不调余额接口、不发飞书、不跑引擎。
import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import { ensureSchema } from "../src/engine/db";
import type { DailyNotifyArgs, DailyStartArgs } from "../src/services/feishu_notify";
import type { BalanceSnapshot } from "../src/services/llm_balance";
import { withDailyRunReport, type RunReportCtx } from "../src/services/run_report";

const RUN_DATE = "2026-09-16";
const TZ = "Asia/Shanghai";
const FIXED = new Date("2026-09-16T00:00:10Z");

const snap = (total: number): BalanceSnapshot => ({ currency: "CNY", total, at: FIXED });

/** ctx：seam 全为记录型假实现；余额按调用次序依次返回 before/after。 */
function makeCtx(balances: (BalanceSnapshot | null)[], overrides: Partial<RunReportCtx> = {}) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  const events: string[] = [];
  const starts: DailyStartArgs[] = [];
  const ends: DailyNotifyArgs[] = [];
  let i = 0;
  const engineCfg: AppConfig = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "rr-cp.sqlite"),
    outputDir: join(tmpdir(), "rr-out"),
  };
  const ctx: RunReportCtx = {
    db,
    serverCfg: loadServerConfig({
      JWT_SECRET: "s".repeat(32),
      ADMIN_JWT_SECRET: "a".repeat(32),
      LLM_API_KEY: "k",
      TIMEZONE: TZ,
    }),
    engineCfg,
    balance: { baseUrl: "https://api.deepseek.com", apiKey: "k" },
    now: () => FIXED,
    probe: async () => {
      events.push("probe");
      return balances[Math.min(i++, balances.length - 1)] ?? null;
    },
    notifyStart: async (_c, a) => {
      events.push("start");
      starts.push(a);
    },
    notifyEnd: async (_c, a) => {
      events.push("end");
      ends.push(a);
    },
    ...overrides,
  };
  return { ctx, events, starts, ends };
}

describe("withDailyRunReport（编排顺序与成本取数）", () => {
  test("正常：查余额 → 开始卡 → 跑 → 查余额 → 结束卡，前后余额分别传入", async () => {
    const { ctx, events, starts, ends } = makeCtx([snap(3.65), snap(3.23)]);
    const out = await withDailyRunReport(ctx, RUN_DATE, async () => {
      events.push("run");
      return { stepErrors: ["槽位 3 补跑失败: boom"] };
    });

    expect(events).toEqual(["probe", "start", "run", "probe", "end"]);
    expect(starts[0]!.runDate).toBe(RUN_DATE);
    expect(starts[0]!.balanceBefore!.total).toBe(3.65);
    expect(ends[0]!.balanceBefore!.total).toBe(3.65);
    expect(ends[0]!.balanceAfter!.total).toBe(3.23);
    expect(ends[0]!.stepErrors).toEqual(["槽位 3 补跑失败: boom"]);
    expect(out.stepErrors).toEqual(["槽位 3 补跑失败: boom"]);
    expect(out.startedAt).toEqual(FIXED);
    expect(out.endedAt).toEqual(FIXED);
  });

  test("运行抛错 → 仍发结束卡（stepErrors 记抛错）并向上重抛", async () => {
    const { ctx, events, ends } = makeCtx([snap(3.65), snap(3.23)]);
    await expect(
      withDailyRunReport(ctx, RUN_DATE, async () => {
        events.push("run");
        throw new Error("LLM 网关挂了");
      }),
    ).rejects.toThrow("LLM 网关挂了");

    expect(events).toEqual(["probe", "start", "run", "probe", "end"]);
    expect(ends).toHaveLength(1);
    expect(ends[0]!.stepErrors![0]).toContain("LLM 网关挂了");
  });

  test("余额查询失败（null）→ 两条卡照发，余额如实为 null（成本未知）", async () => {
    const { ctx, starts, ends } = makeCtx([null, null]);
    await withDailyRunReport(ctx, RUN_DATE, async () => ({ stepErrors: [] }));
    expect(starts[0]!.balanceBefore).toBeNull();
    expect(ends[0]!.balanceBefore).toBeNull();
    expect(ends[0]!.balanceAfter).toBeNull();
  });

  test("通知 seam 抛错 → 不阻断运行（通知故障绝不中断生成）", async () => {
    const { ctx, events } = makeCtx([snap(3.65), snap(3.23)], {
      notifyStart: async () => {
        throw new Error("feishu down");
      },
      notifyEnd: async () => {
        throw new Error("feishu down");
      },
    });
    const out = await withDailyRunReport(ctx, RUN_DATE, async () => {
      events.push("run");
      return { stepErrors: [] };
    });
    expect(events).toContain("run"); // 开始卡发失败也照跑
    expect(out.stepErrors).toEqual([]);
  });
});
