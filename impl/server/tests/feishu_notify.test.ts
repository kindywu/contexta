// 每日生成完成 → 飞书通知（签名/报告/卡片/去重/非抛）：
// - 签名算法与独立实现（python hmac）固定向量对照，防"测试抄生产实现"循环验证
// - 报告从真实 :memory: 库（引擎表 + 服务端表）汇总；fetch 注入假实现，不真发网络
import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { ensureSchema, createBatchAndSlots, finalizeBatch, listSlots, writeSlotResult } from "../src/engine/db";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import { loadServerConfig, type ServerConfig } from "../src/config";
import {
  buildAlertCard,
  buildDailyCard,
  buildDailyReport,
  buildRecheckCard,
  buildStartCard,
  formatCostLine,
  formatDuration,
  formatTime,
  lowBalanceWarning,
  notifyDailyCostRecheck,
  notifyDailyResult,
  notifyDailyStart,
  notifyDailyUnclosed,
  sendFeishu,
  signFeishu,
  truncateLine,
  type DailyNotifyArgs,
  type FeishuNotifyCtx,
} from "../src/services/feishu_notify";
import type { BalanceSnapshot } from "../src/services/llm_balance";
import type { SlotStatus } from "../src/engine/db";

const TZ = "Asia/Shanghai";
const RUN_DATE = "2026-09-09";
/** 固定时刻：测试内 startedAt/endedAt/now 注入一致，payload timestamp 可精确断言。 */
const FIXED_TIME = new Date("2026-09-09T00:10:12Z");

function newDb(): Database {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  return db;
}

function serverCfg(overrides: Partial<Record<string, string>> = {}): ServerConfig {
  return loadServerConfig({
    JWT_SECRET: "s".repeat(32),
    ADMIN_JWT_SECRET: "a".repeat(32),
    LLM_API_KEY: "k",
    TIMEZONE: TZ,
    FEISHU_WEBHOOK_URL: "https://open.feishu.cn/open-apis/bot/v2/hook/test-hook",
    FEISHU_WEBHOOK_SECRET: "test-secret",
    ...overrides,
  });
}

function engineCfg(): AppConfig {
  return {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "fn-cp.sqlite"),
    outputDir: join(tmpdir(), "fn-out"),
  };
}

interface SeedSlot {
  status: SlotStatus;
  reason?: string;
  attempts?: number;
}

/** 建批次 + 槽位并落终态（含 error_message）；返回批次 id。 */
function seedDay(db: Database, slots: SeedSlot[], close = true): number {
  const batch = createBatchAndSlots(
    db,
    RUN_DATE,
    slots.length,
    slots.map((_, i) => ({
      slotIndex: i,
      difficulty: (i % 2 === 0 ? "LOW" : "MEDIUM") as "LOW" | "MEDIUM",
      threadId: `daily-${RUN_DATE}-${i}`,
    })),
  );
  const rows = listSlots(db, RUN_DATE);
  slots.forEach((s, i) => {
    if (s.status === "pending") return;
    writeSlotResult(db, {
      slotId: rows[i]!.id,
      threadId: rows[i]!.threadId,
      status: s.status,
      errorMessage: s.reason,
      attempts: s.attempts ?? 1,
    });
  });
  if (close) finalizeBatch(db, batch.id);
  return batch.id;
}

function args(overrides: Partial<DailyNotifyArgs> = {}): DailyNotifyArgs {
  return { runDate: RUN_DATE, startedAt: FIXED_TIME, endedAt: FIXED_TIME, ...overrides };
}

/** fetch 假实现：记录请求，返回固定响应。 */
function fakeFetch(body: Array<Record<string, unknown>>, response: { ok: boolean; code: number; msg: string }) {
  const calls: { url: string; payload: Record<string, unknown> }[] = [];
  const fn = (async (url: string, init: RequestInit) => {
    calls.push({ url, payload: JSON.parse(String(init.body)) as Record<string, unknown> });
    return new Response(JSON.stringify({ code: response.code, msg: response.msg }), {
      status: response.ok ? 200 : 500,
      headers: { "content-type": "application/json" },
    });
  }) as unknown as typeof fetch;
  return { fn, calls };
}

function notifyCtx(overrides: Partial<FeishuNotifyCtx> = {}): FeishuNotifyCtx {
  return {
    db: newDb(),
    serverCfg: serverCfg(),
    engineCfg: engineCfg(),
    notified: new Set(),
    now: () => FIXED_TIME,
    ...overrides,
  };
}

describe("signFeishu（自定义机器人签名）", () => {
  test("与独立实现（python hmac）固定向量一致", () => {
    expect(signFeishu("test-signature", "1622262881")).toBe("+5oBQji+Mjw1DVNyxwP/Wh95qWHgA9kc+mQe0N6UOTQ=");
  });
  test("timestamp/secret 参与签名：任一份变化 → 签名不同", () => {
    const base = signFeishu("secret-1", "1000");
    expect(signFeishu("secret-1", "1001")).not.toBe(base);
    expect(signFeishu("secret-2", "1000")).not.toBe(base);
  });
});

describe("formatDuration / formatTime / truncateLine", () => {
  test("formatDuration: 秒 / 分 / 小时三档", () => {
    expect(formatDuration(43_000)).toBe("43 秒");
    expect(formatDuration(753_000)).toBe("12 分 33 秒");
    expect(formatDuration(3_723_000)).toBe("1 小时 2 分 3 秒");
  });
  test("formatTime: 配置时区 HH:mm:ss", () => {
    expect(formatTime(new Date("2026-09-09T00:00:12Z"), TZ)).toBe("08:00:12");
  });
  test("truncateLine: 超长截断加省略号，短文本原样", () => {
    expect(truncateLine("x".repeat(130))).toHaveLength(121);
    expect(truncateLine("短原因")).toBe("短原因");
  });
});

describe("buildDailyReport（库内现状汇总）", () => {
  test("收口批次：计数 + 失败明细（error/rejected 带真实原因，其余不进失败明细）", () => {
    const db = newDb();
    seedDay(db, [
      { status: "success", reason: "此前失败残留" }, // 上次失败原因应被 success 清空
      { status: "success" },
      { status: "error", reason: "LLM 调用超时", attempts: 2 },
      { status: "rejected", reason: "文章抓取失败", attempts: 1 },
      { status: "pending" },
    ]);
    const report = buildDailyReport(db, args(), TZ);
    expect(report.batchStatus).toBe("completed_with_failures");
    expect(report.totalSlots).toBe(5);
    expect(report.success).toBe(2);
    expect(report.error).toBe(1);
    expect(report.rejected).toBe(1);
    expect(report.pending).toBe(1);
    expect(report.durationMs).toBe(0);
    expect(report.failures).toEqual([
      { slotIndex: 2, difficulty: "LOW", status: "error", attempts: 2, reason: "LLM 调用超时" },
      { slotIndex: 3, difficulty: "MEDIUM", status: "rejected", attempts: 1, reason: "文章抓取失败" },
    ]);
  });
  test("全成功：completed，失败明细为空", () => {
    const db = newDb();
    seedDay(db, [{ status: "success" }, { status: "success" }]);
    const report = buildDailyReport(db, args(), TZ);
    expect(report.batchStatus).toBe("completed");
    expect(report.failures).toHaveLength(0);
  });
  test("未收口（running）与无批次（none）：状态如实反映", () => {
    const db = newDb();
    seedDay(db, [{ status: "pending" }], false); // 不收口
    expect(buildDailyReport(db, args(), TZ).batchStatus).toBe("running");
    const db2 = newDb(); // 无批次无槽位
    const r = buildDailyReport(db2, args(), TZ);
    expect(r.batchStatus).toBe("none");
    expect(r.totalSlots).toBe(0);
  });
  test("旧数据无 error_message → 占位原因（不崩）", () => {
    const db = newDb();
    seedDay(db, [{ status: "error" }]);
    db
      .query("UPDATE batch_slots SET error_message = NULL")
      .run();
    const report = buildDailyReport(db, args(), TZ);
    expect(report.failures[0]!.reason).toContain("原因未持久化");
  });
});

describe("buildDailyCard（交互卡片）", () => {
  test("全成功：green 模板，无失败明细/未收口区块", () => {
    const db = newDb();
    seedDay(db, [{ status: "success" }, { status: "success" }]);
    const card = buildDailyCard(buildDailyReport(db, args(), TZ)) as Record<string, any>;
    expect(card.header.template).toBe("green");
    expect(card.header.title.content).toContain(RUN_DATE);
    const text = JSON.stringify(card.elements);
    expect(text).toContain("成功 2/2");
    expect(text).not.toContain("失败明细");
    expect(text).not.toContain("未收口");
  });
  test("有失败：red 模板 + 失败明细含槽位/难度/原因", () => {
    const db = newDb();
    seedDay(db, [
      { status: "success" },
      { status: "error", reason: "LLM 调用超时", attempts: 2 },
      { status: "rejected", reason: "抓取失败" },
    ]);
    const card = buildDailyCard(buildDailyReport(db, args(), TZ)) as Record<string, any>;
    expect(card.header.template).toBe("red");
    const text = JSON.stringify(card.elements);
    expect(text).toContain("失败明细");
    expect(text).toContain("槽位 1");
    expect(text).toContain("LLM 调用超时");
    expect(text).toContain("槽位 2");
  });
  test("未收口（running）：orange 模板 + 步骤错误区块", () => {
    const db = newDb();
    seedDay(db, [{ status: "pending" }], false);
    const card = buildDailyCard(
      buildDailyReport(db, args({ stepErrors: ["引擎生成失败: Error: LLM 网关挂了"] }), TZ),
    ) as Record<string, any>;
    expect(card.header.template).toBe("orange");
    expect(JSON.stringify(card.elements)).toContain("批次未收口");
    expect(JSON.stringify(card.elements)).toContain("引擎生成失败");
  });
});

describe("sendFeishu（签名 payload + 失败语义）", () => {
  test("payload 含 timestamp/sign/msg_type/card，签名与 timestamp 匹配", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    await sendFeishu({ fetch: fn, now: () => FIXED_TIME }, "https://hook", "test-secret", { k: 1 } as never);
    expect(calls).toHaveLength(1);
    const { url, payload } = calls[0]!;
    expect(url).toBe("https://hook");
    expect(payload.timestamp).toBe(Math.floor(FIXED_TIME.getTime() / 1000).toString());
    expect(payload.sign).toBe(signFeishu("test-secret", String(payload.timestamp)));
    expect(payload.msg_type).toBe("interactive");
    expect(payload.card).toEqual({ k: 1 });
  });
  test("code != 0（失败响应）→ 抛错", async () => {
    const { fn } = fakeFetch([], { ok: true, code: 19001, msg: "bad" });
    await expect(sendFeishu({ fetch: fn, now: () => FIXED_TIME }, "https://hook", "s", {} as never)).rejects.toThrow();
  });
  test("HTTP 非 200 → 抛错", async () => {
    const { fn } = fakeFetch([], { ok: false, code: -1, msg: "err" });
    await expect(sendFeishu({ fetch: fn, now: () => FIXED_TIME }, "https://hook", "s", {} as never)).rejects.toThrow();
  });
});

describe("notifyDailyResult（编排：跳过/去重/非抛）", () => {
  test("未配置 webhook → 跳过，fetch 不被调用", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    await notifyDailyResult(
      notifyCtx({ serverCfg: serverCfg({ FEISHU_WEBHOOK_URL: "", FEISHU_WEBHOOK_SECRET: "" }), fetch: fn }),
      args(),
    );
    expect(calls).toHaveLength(0);
  });
  test("发送成功后发送：payload 卡片、通知集合记账；并发/重复触发 → 去重只发一次", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const notified = new Set<string>();
    const ctx = notifyCtx({ fetch: fn, notified });
    seedDay(ctx.db, [{ status: "error", reason: "LLM 超时" }]);
    await notifyDailyResult(ctx, args());
    await notifyDailyResult(ctx, args()); // 同日第二次 → 去重
    expect(calls).toHaveLength(1);
    expect(notified.has(`${RUN_DATE}:end`)).toBe(true);
    const payload = calls[0]!.payload;
    expect(payload.msg_type).toBe("interactive");
    expect(JSON.stringify(payload.card)).toContain("LLM 超时");
  });
  test("发送失败（fetch 抛错）→ 不抛（记日志），且不记账（再次触发重试）", async () => {
    let attempts = 0;
    const fn = (async () => {
      attempts += 1;
      throw new Error("network down");
    }) as unknown as typeof fetch;
    const ctx = notifyCtx({ fetch: fn, notified: new Set() });
    seedDay(ctx.db, [{ status: "success" }]);
    await notifyDailyResult(ctx, args()); // 不抛
    await notifyDailyResult(ctx, args()); // 未记账 → 再试
    expect(attempts).toBe(2);
  });
  test("批次未收口（running）→ 仍发送（未收口报告）", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const ctx = notifyCtx({ fetch: fn });
    seedDay(ctx.db, [{ status: "pending" }], false);
    await notifyDailyResult(ctx, args({ stepErrors: ["引擎生成失败: boom"] }));
    expect(calls).toHaveLength(1);
    expect(JSON.stringify(calls[0]!.payload.card)).toContain("批次未收口");
  });
  test("发送失败响应（code != 0）→ 不抛", async () => {
    const { fn } = fakeFetch([], { ok: true, code: 19001, msg: "bad" });
    const ctx = notifyCtx({ fetch: fn });
    await expect(notifyDailyResult(ctx, args())).resolves.toBeUndefined();
  });
});

// ───────────────────────── 余额 / 开始卡 / 告警卡（新增） ─────────────────────────

/** 余额快照构造器（at 固定，断言可精确）。 */
const snap = (total: number, currency = "CNY"): BalanceSnapshot => ({ currency, total, at: FIXED_TIME });

describe("formatCostLine（本次成本渲染）", () => {
  test("余额下降 → 成本 = 差值，括号内给出前后余额", () => {
    expect(formatCostLine({ currency: "CNY", before: 3.65, after: 3.23 })).toBe(
      "本次成本 ≈ ¥0.42（3.65 → 3.23）",
    );
  });
  test("余额未变 → 标注计费延迟尚未结算（不假装本次免费）", () => {
    const line = formatCostLine({ currency: "CNY", before: 3.23, after: 3.23 });
    expect(line).toContain("¥0.00");
    expect(line).toContain("延迟");
  });
  test("余额增加 → 标注多为充值，且不出现负数成本", () => {
    const line = formatCostLine({ currency: "CNY", before: 3.23, after: 13.23 });
    expect(line).toContain("充值");
    expect(line).not.toContain("-");
  });
  test("余额未知（查询失败）→ 成本未知", () => {
    expect(formatCostLine(null)).toContain("未知");
  });
  test("非 CNY 币种 → 用币种代码而非 ¥", () => {
    const line = formatCostLine({ currency: "USD", before: 1, after: 0.9 });
    expect(line).toContain("USD");
    expect(line).not.toContain("¥");
  });
});

describe("lowBalanceWarning（低余额提醒）", () => {
  test("低于阈值 → 文案含阈值与当前余额", () => {
    const w = lowBalanceWarning(snap(0.83));
    expect(w).toContain("充值");
    expect(w).toContain("¥1");
    expect(w).toContain("0.83");
  });
  test("达标或未知 → null（查不到余额不误报）", () => {
    expect(lowBalanceWarning(snap(1))).toBeNull();
    expect(lowBalanceWarning(snap(50))).toBeNull();
    expect(lowBalanceWarning(null)).toBeNull();
  });
});

describe("buildStartCard（开始卡）", () => {
  test("含日期 / 开始时刻（配置时区）/ 运行前余额", () => {
    const card = buildStartCard(
      { runDate: RUN_DATE, startedAt: FIXED_TIME, balanceBefore: snap(3.23) },
      TZ,
    ) as Record<string, any>;
    expect(card.header.title.content).toContain(RUN_DATE);
    const text = JSON.stringify(card.elements);
    expect(text).toContain("08:10:12"); // FIXED_TIME = 00:10:12Z → Asia/Shanghai
    expect(text).toContain("3.23");
  });
  test("余额低于阈值 → 带充值提醒", () => {
    const card = buildStartCard(
      { runDate: RUN_DATE, startedAt: FIXED_TIME, balanceBefore: snap(0.83) },
      TZ,
    ) as Record<string, any>;
    expect(JSON.stringify(card.elements)).toContain("充值");
  });
  test("余额未知 → 如实显示查询失败，不编造数字", () => {
    const card = buildStartCard(
      { runDate: RUN_DATE, startedAt: FIXED_TIME, balanceBefore: null },
      TZ,
    ) as Record<string, any>;
    const text = JSON.stringify(card.elements);
    expect(text).toContain("查询失败");
    expect(text).not.toContain("充值");
  });
});

describe("buildAlertCard（未收口告警卡）", () => {
  const CHECKED = new Date("2026-09-09T01:15:00Z"); // 09:15:00 Asia/Shanghai
  test("无批次 → 指明批次不存在", () => {
    const card = buildAlertCard({ runDate: RUN_DATE, checkedAt: CHECKED, batchStatus: "none" }, TZ) as Record<string, any>;
    expect(card.header.title.content).toContain(RUN_DATE);
    const text = JSON.stringify(card.elements);
    expect(text).toContain("09:15:00");
    expect(text).toContain("不存在");
  });
  test("批次仍 running → 指明未收口", () => {
    const card = buildAlertCard({ runDate: RUN_DATE, checkedAt: CHECKED, batchStatus: "running" }, TZ) as Record<string, any>;
    const text = JSON.stringify(card.elements);
    expect(text).toContain("未收口");
    expect(text).toContain("running");
  });
});

describe("notifyDailyStart / notifyDailyUnclosed（编排：记账与去重按阶段）", () => {
  test("开始卡与结束卡互不干扰：各发一条、各自记账、各自去重", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const notified = new Set<string>();
    const ctx = notifyCtx({ fetch: fn, notified });
    seedDay(ctx.db, [{ status: "success" }]);
    const startArgs = { runDate: RUN_DATE, startedAt: FIXED_TIME, balanceBefore: snap(3.23) };

    await notifyDailyStart(ctx, startArgs);
    await notifyDailyResult(ctx, args());
    expect(calls).toHaveLength(2);
    expect(notified.has(`${RUN_DATE}:start`)).toBe(true);
    expect(notified.has(`${RUN_DATE}:end`)).toBe(true);

    await notifyDailyStart(ctx, startArgs); // 已发过 → 去重
    await notifyDailyResult(ctx, args());
    expect(calls).toHaveLength(2);
  });
  test("未配置 webhook → 开始卡与告警卡都静默跳过", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const ctx = notifyCtx({
      serverCfg: serverCfg({ FEISHU_WEBHOOK_URL: "", FEISHU_WEBHOOK_SECRET: "" }),
      fetch: fn,
    });
    await notifyDailyStart(ctx, { runDate: RUN_DATE, startedAt: FIXED_TIME, balanceBefore: null });
    await notifyDailyUnclosed(ctx, { runDate: RUN_DATE, checkedAt: FIXED_TIME, batchStatus: "none" });
    expect(calls).toHaveLength(0);
  });
  test("告警卡发送失败 → 不抛（看门狗不得因通知失败而中断）", async () => {
    const fn = (async () => {
      throw new Error("network down");
    }) as unknown as typeof fetch;
    const ctx = notifyCtx({ fetch: fn, notified: new Set() });
    await expect(
      notifyDailyUnclosed(ctx, { runDate: RUN_DATE, checkedAt: FIXED_TIME, batchStatus: "running" }),
    ).resolves.toBeUndefined();
  });
});

describe("buildRecheckCard / notifyDailyCostRecheck（余额复核卡）", () => {
  const CHECKED = new Date("2026-09-17T00:20:00Z"); // 08:20:00 Asia/Shanghai
  const recheckArgs = (settled: BalanceSnapshot | null) => ({
    runDate: RUN_DATE,
    checkedAt: CHECKED,
    balanceBefore: snap(3.65),
    balanceAfter: snap(3.65),
    balanceSettled: settled,
  });

  test("结算到账：复核结果按运行前余额折算真实成本，含结束卡 0 成本与复核时刻", () => {
    const card = buildRecheckCard(recheckArgs(snap(3.23)), TZ) as Record<string, any>;
    expect(card.header.title.content).toContain(RUN_DATE);
    const text = JSON.stringify(card.elements);
    expect(text).toContain("¥0.00"); // 结束卡当时的成本
    expect(text).toContain("08:20:00"); // 复核时刻（配置时区）
    expect(text).toContain("0.42"); // 3.65 → 3.23
  });
  test("复核时仍未变化 → 如实标注未消耗/结算更久，不编造成本", () => {
    const card = buildRecheckCard(recheckArgs(snap(3.65)), TZ) as Record<string, any>;
    const text = JSON.stringify(card.elements);
    expect(text).toContain("仍未变化");
  });
  test("复核时余额增加 → 标注多为充值", () => {
    const card = buildRecheckCard(recheckArgs(snap(13.65)), TZ) as Record<string, any>;
    expect(JSON.stringify(card.elements)).toContain("充值");
  });
  test("复核查询失败 → 标未知可手动核对；复核余额低 → 带充值提醒", () => {
    const failed = buildRecheckCard(recheckArgs(null), TZ) as Record<string, any>;
    expect(JSON.stringify(failed.elements)).toContain("查询失败");

    const low = buildRecheckCard(recheckArgs(snap(0.5)), TZ) as Record<string, any>;
    expect(JSON.stringify(low.elements)).toContain("充值");
  });
  test("发送：进入 recheck 阶段记账（与 end 互不干扰），同日重复触发去重", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const notified = new Set<string>();
    const ctx = notifyCtx({ fetch: fn, notified });
    await notifyDailyCostRecheck(ctx, recheckArgs(snap(3.23)));
    await notifyDailyCostRecheck(ctx, recheckArgs(snap(3.23)));
    expect(calls).toHaveLength(1);
    expect(notified.has(`${RUN_DATE}:recheck`)).toBe(true);
  });
  test("发送失败 → 不抛；未配置 webhook → 静默跳过", async () => {
    const fail = (async () => {
      throw new Error("network down");
    }) as unknown as typeof fetch;
    await expect(notifyDailyCostRecheck(notifyCtx({ fetch: fail }), recheckArgs(null))).resolves.toBeUndefined();

    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    await notifyDailyCostRecheck(
      notifyCtx({ serverCfg: serverCfg({ FEISHU_WEBHOOK_URL: "", FEISHU_WEBHOOK_SECRET: "" }), fetch: fn }),
      recheckArgs(null),
    );
    expect(calls).toHaveLength(0);
  });
});

describe("notifyDailyResult 的余额扩展（成本进结束卡）", () => {
  test("传入前后余额 → 结束卡含本次成本", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const ctx = notifyCtx({ fetch: fn });
    seedDay(ctx.db, [{ status: "success" }]);
    await notifyDailyResult(ctx, args({ balanceBefore: snap(3.65), balanceAfter: snap(3.23) }));
    const text = JSON.stringify(calls[0]!.payload.card);
    expect(text).toContain("本次成本");
    expect(text).toContain("0.42");
  });
  test("余额低于阈值 → 结束卡带充值提醒", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const ctx = notifyCtx({ fetch: fn });
    seedDay(ctx.db, [{ status: "success" }]);
    await notifyDailyResult(ctx, args({ balanceBefore: snap(1.5), balanceAfter: snap(0.83) }));
    expect(JSON.stringify(calls[0]!.payload.card)).toContain("充值");
  });
  test("未传余额（缺省）→ 结束卡标成本未知，不崩", async () => {
    const { fn, calls } = fakeFetch([], { ok: true, code: 0, msg: "success" });
    const ctx = notifyCtx({ fetch: fn });
    seedDay(ctx.db, [{ status: "success" }]);
    await notifyDailyResult(ctx, args());
    expect(JSON.stringify(calls[0]!.payload.card)).toContain("未知");
  });
});
