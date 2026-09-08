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
  buildDailyCard,
  buildDailyReport,
  formatDuration,
  formatTime,
  notifyDailyResult,
  sendFeishu,
  signFeishu,
  truncateLine,
  type DailyNotifyArgs,
  type FeishuNotifyCtx,
} from "../src/services/feishu_notify";
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
    expect(notified.has(RUN_DATE)).toBe(true);
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
