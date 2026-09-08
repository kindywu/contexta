// src/services/feishu_notify.ts
// 每日生成完成 → 飞书群机器人通知（自定义 Webhook + 签名签体）：
// - 触发：每日窗口 runFill 后 / 管理端手动 generate 后（触发点在 daily_task 与 admin.ts）
// - 内容：执行日期/起止时间/耗时、成功与失败/拒绝/待定计数、失败槽位真实原因、
//   批次状态；批次未收口（收口 = status != running）时附运行步骤错误
// - 纪律：通知任何失败只记日志绝不抛——通知永不中断生成流程；未配置 webhook 静默跳过；
//   按 runDate 去重（进程内当日只发第一条，发送成功才记账）
// - 签名：自定义机器人签名算法——base64(HMAC-SHA256(key = `${timestamp}\n${secret}`))，
//   timestamp 为秒级字符串且 payload 内 timestamp 必须与签名一致
import { createHmac } from "node:crypto";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { getBatch, listSlots } from "../engine/db";
import { log } from "../engine/graph/log";

/** 通知入参（触发点统一口径）：本次运行的起止时刻 + 运行内部步骤错误。 */
export interface DailyNotifyArgs {
  runDate: string;
  startedAt: Date;
  endedAt: Date;
  /** 运行步骤错误（引擎生成/pending 恢复/补跑/审核行补齐的 catch 文本）；批次未收口时展示 */
  stepErrors?: string[];
}

/** 通知函数 seam（DailyTask/admin 注入假实现；缺省 = notifyDailyResult 闭包）。 */
export type DailyNotifyFn = (args: DailyNotifyArgs) => Promise<void>;

export interface FeishuNotifyCtx {
  db: Database;
  serverCfg: ServerConfig;
  engineCfg: AppConfig;
  /** 网络 seam：缺省全局 fetch（测试注入假实现） */
  fetch?: typeof fetch;
  /** 时钟 seam：缺省 new Date */
  now?: () => Date;
  /** 去重 set seam：缺省模块级 notifiedDates（测试传独立 set 隔离） */
  notified?: Set<string>;
}

/** 模块级去重（进程生命周期内同日只发第一条；发送成功才记账）。 */
export const notifiedDates = new Set<string>();

/** 飞书自定义机器人签名：base64(HMAC-SHA256(key = `${timestamp}\n${secret}`))。 */
export function signFeishu(secret: string, timestamp: string): string {
  return createHmac("sha256", `${timestamp}\n${secret}`).digest("base64");
}

/** 耗时格式化：<60s → "43 秒"；<1h → "12 分 33 秒"；否则 "1 小时 2 分 3 秒"。 */
export function formatDuration(ms: number): string {
  const totalSec = Math.round(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h} 小时 ${m} 分 ${s} 秒`;
  if (m > 0) return `${m} 分 ${s} 秒`;
  return `${s} 秒`;
}

/** 时刻格式化（配置时区）："08:00:12"。 */
export function formatTime(d: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).format(d);
}

/** 截断单行：超长只留前 maxLen 字符 + "…"（飞书卡片单行宽度有限）。 */
export function truncateLine(s: string, maxLen = 120): string {
  return s.length > maxLen ? `${s.slice(0, maxLen)}…` : s;
}

/** 每日运行报告（从当前库内批次/槽位现状汇总，与引擎运行态无关）。 */
export interface DailyRunReport {
  runDate: string;
  timeZone: string;
  startedAt: Date;
  endedAt: Date;
  durationMs: number;
  /** article_batches.status；无批次 → "none" */
  batchStatus: string;
  totalSlots: number;
  success: number;
  error: number;
  rejected: number;
  pending: number;
  /** 失败/拒绝槽位明细（error + rejected），按槽位号序 */
  failures: Array<{
    slotIndex: number;
    difficulty: string;
    status: string;
    attempts: number;
    reason: string;
  }>;
  stepErrors: string[];
}

export function buildDailyReport(db: Database, args: DailyNotifyArgs, timeZone: string): DailyRunReport {
  const batch = getBatch(db, args.runDate);
  const slots = listSlots(db, args.runDate);
  const success = slots.filter((s) => s.status === "success").length;
  const error = slots.filter((s) => s.status === "error").length;
  const rejected = slots.filter((s) => s.status === "rejected").length;
  const pending = slots.filter((s) => s.status === "pending").length;
  const failures = slots
    .filter((s) => s.status === "error" || s.status === "rejected")
    .map((s) => ({
      slotIndex: s.slotIndex,
      difficulty: s.difficulty,
      status: s.status,
      attempts: s.attempts,
      reason: s.errorMessage ?? "原因未持久化（详见运行日志）",
    }));
  return {
    runDate: args.runDate,
    timeZone,
    startedAt: args.startedAt,
    endedAt: args.endedAt,
    durationMs: Math.max(0, args.endedAt.getTime() - args.startedAt.getTime()),
    batchStatus: batch?.status ?? "none",
    totalSlots: slots.length,
    success,
    error,
    rejected,
    pending,
    failures,
    stepErrors: args.stepErrors ?? [],
  };
}

/**
 * 构建交互卡片（自定义机器人卡片每次全新发送，无 card_id 更新）。返回对象为
 * 飞书 interactive card schema：header + elements（lark_md 文本）。
 */
export function buildDailyCard(report: DailyRunReport): Record<string, unknown> {
  const unclosed = report.batchStatus === "running" || report.batchStatus === "none";
  const allOk = report.batchStatus === "completed";
  const template = unclosed ? "orange" : allOk ? "green" : "red";
  const emoji = allOk ? "✅" : unclosed ? "⚠️" : "🔶";
  const lines = [
    `**执行日期**：${report.runDate}（${report.timeZone}）`,
    `**开始**：${formatTime(report.startedAt, report.timeZone)}　**结束**：${formatTime(report.endedAt, report.timeZone)}　**耗时**：${formatDuration(report.durationMs)}`,
    `**结果**：成功 ${report.success}/${report.totalSlots} · 失败 ${report.error + report.rejected}（error ${report.error} / rejected ${report.rejected}）· 待定 ${report.pending}`,
  ];
  const elements: Record<string, unknown>[] = [
    { tag: "div", text: { tag: "lark_md", content: lines.join("\n") } },
  ];
  if (report.failures.length > 0) {
    const detail = report.failures
      .map(
        (f, i) =>
          `**${i + 1}. 槽位 ${f.slotIndex}**（${f.difficulty} · ${f.status} · ${f.attempts} 次尝试）：${truncateLine(f.reason)}`,
      )
      .join("\n");
    elements.push({ tag: "hr" });
    elements.push({ tag: "div", text: { tag: "lark_md", content: `**失败明细**（${report.failures.length}）\n${detail}` } });
  }
  if (unclosed) {
    elements.push({ tag: "hr" });
    const steps =
      report.stepErrors.length > 0
        ? report.stepErrors.map((s, i) => `**${i + 1}.** ${truncateLine(s)}`).join("\n")
        : "批次未收口（status=running）——进程中断/未完成，待明日窗口或手动补跑";
    elements.push({ tag: "div", text: { tag: "lark_md", content: `**⚠️ 批次未收口**\n${steps}` } });
  }
  return {
    config: { wide_screen_mode: true },
    header: { template, title: { tag: "plain_text", content: `${emoji} 每日文章生成报告 · ${report.runDate}` } },
    elements,
  };
}

/**
 * 发送一张卡片到自定义机器人 webhook：签名 timestamp 必须与 payload 一致（秒级字符串）。
 * 非 200 或 body.code != 0（失败响应）→ 抛错（由调用方记日志，不影响生成流程）。
 */
export async function sendFeishu(
  ctx: Pick<FeishuNotifyCtx, "fetch" | "now">,
  webhookUrl: string,
  secret: string,
  card: Record<string, unknown>,
): Promise<void> {
  const timestamp = Math.floor(((ctx.now?.() ?? new Date()).getTime()) / 1000).toString();
  const body = JSON.stringify({ timestamp, sign: signFeishu(secret, timestamp), msg_type: "interactive", card });
  const res = await (ctx.fetch ?? fetch)(webhookUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
    signal: AbortSignal.timeout(5000),
  });
  let data: { code?: number; msg?: string } = {};
  try {
    data = (await res.json()) as typeof data;
  } catch {
    // 非 JSON 响应按失败处理
  }
  if (!res.ok || data.code !== 0) {
    throw new Error(`飞书 webhook 失败: http=${res.status} code=${data.code ?? "?"} msg=${data.msg ?? ""}`);
  }
}

/**
 * 每日运行结束后的通知入口（非抛）：未配置 webhook / 当日已发 → 跳过；
 * 发送成功才记账。任何失败仅记日志（通知不得中断生成流程）。
 */
export async function notifyDailyResult(ctx: FeishuNotifyCtx, args: DailyNotifyArgs): Promise<void> {
  const { serverCfg, db, engineCfg } = ctx;
  if (!serverCfg.feishuWebhookUrl || !serverCfg.feishuWebhookSecret) {
    log(`[feishu-notify] ${args.runDate} 未配置 FEISHU_WEBHOOK_URL/FEISHU_WEBHOOK_SECRET，跳过通知`);
    return;
  }
  const notified = ctx.notified ?? notifiedDates;
  if (notified.has(args.runDate)) {
    log(`[feishu-notify] ${args.runDate} 今日已发送过，跳过（去重）`);
    return;
  }
  const report = buildDailyReport(db, args, engineCfg.timezone);
  try {
    await sendFeishu(ctx, serverCfg.feishuWebhookUrl, serverCfg.feishuWebhookSecret, buildDailyCard(report));
    notified.add(args.runDate);
    log(
      `[feishu-notify] ${args.runDate} 通知已发送（成功 ${report.success}/${report.totalSlots}，失败 ${report.error + report.rejected}）`,
    );
  } catch (err) {
    log(`[feishu-notify] ${args.runDate} 通知发送失败（不影响生成流程）: ${err instanceof Error ? err.message : String(err)}`);
  }
}
