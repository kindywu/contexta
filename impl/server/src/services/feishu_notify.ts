// src/services/feishu_notify.ts
// 每日运行 → 飞书群机器人通知（自定义 Webhook + 签名签体）：一次运行两条消息 + 一条独立告警。
// - 触发：每日窗口 runFill / 管理端手动 generate（触发点在 run_report.ts 的包装里）；
//   告警由 daily_alert.ts 的独立看门狗触发（不依赖生成循环是否活着）
// - 开始卡（notifyDailyStart）：执行日期、开始时刻、运行前余额（低余额时附充值提醒）
// - 结束卡（notifyDailyResult）：起止/耗时、成功与失败/拒绝/待定计数、失败槽位真实原因、
//   批次状态、本次成本（运行前后余额差；未收口时附运行步骤错误）
// - 未收口告警（notifyDailyUnclosed）：窗口结束仍未收口/无批次——"有开始没结束"的自动判定
// - 纪律：通知任何失败只记日志绝不抛——通知永不中断生成流程；未配置 webhook 静默跳过；
//   按 `${runDate}:${phase}` 去重（进程内每条只发一次，发送成功才记账）
// - 签名：自定义机器人签名算法——base64(HMAC-SHA256(key = `${timestamp}\n${secret}`))，
//   timestamp 为秒级字符串且 payload 内 timestamp 必须与签名一致
import { createHmac } from "node:crypto";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { getBatch, listSlots } from "../engine/db";
import { log } from "../engine/graph/log";
import {
  isLowBalance,
  LOW_BALANCE_THRESHOLD,
  type BalanceSnapshot,
} from "./llm_balance";

/** 通知入参（触发点统一口径）：本次运行的起止时刻 + 运行内部步骤错误。 */
export interface DailyNotifyArgs {
  runDate: string;
  startedAt: Date;
  endedAt: Date;
  /** 运行步骤错误（引擎生成/pending 恢复/补跑/审核行补齐的 catch 文本）；批次未收口时展示 */
  stepErrors?: string[];
  /** 运行前余额快照（缺省/null = 未查询或查询失败 → 成本未知） */
  balanceBefore?: BalanceSnapshot | null;
  /** 运行后余额快照（充值提醒依据） */
  balanceAfter?: BalanceSnapshot | null;
}

/** 通知阶段：同日最多四条（start/end/alert/recheck），去重键 = `${runDate}:${phase}`。 */
export type NotifyPhase = "start" | "end" | "alert" | "recheck";

/** 开始卡入参。 */
export interface DailyStartArgs {
  runDate: string;
  startedAt: Date;
  /** 运行前余额（null = 查询失败，卡片如实标注） */
  balanceBefore: BalanceSnapshot | null;
}

/** 未收口告警入参（看门狗触发）。 */
export interface DailyAlertArgs {
  runDate: string;
  /** 检查时刻（配置时区渲染） */
  checkedAt: Date;
  /** 检查时的批次状态：getBatch 的 status，无批次传 "none" */
  batchStatus: string;
}

/** 余额复核入参（结束卡成本为 0 时，延迟 10 分钟后的第二次余额快照）。 */
export interface DailyRecheckArgs {
  runDate: string;
  /** 复核时刻（第二次余额查询时刻） */
  checkedAt: Date;
  /** 结束卡时的运行前余额（与 balanceAfter 相等 = 成本 0 的判定依据） */
  balanceBefore: BalanceSnapshot;
  /** 结束卡时的运行后余额 */
  balanceAfter: BalanceSnapshot;
  /** 复核余额快照（null = 查询失败） */
  balanceSettled: BalanceSnapshot | null;
}

/** 本次运行成本（余额差；currency 取运行后快照）。 */
export interface DailyCost {
  currency: string;
  before: number;
  after: number;
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

/** 模块级去重（进程生命周期内每条只发一次；键 = `${runDate}:${phase}`；发送成功才记账）。 */
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
  /** 本次运行成本（余额差）；任一侧余额缺失 → null（渲染为"未知"） */
  cost: DailyCost | null;
  /** 运行后余额快照（渲染低余额提醒）；未知 → null */
  balanceAfter: BalanceSnapshot | null;
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
  const before = args.balanceBefore ?? null;
  const after = args.balanceAfter ?? null;
  return {
    runDate: args.runDate,
    timeZone,
    cost: before && after ? { currency: after.currency, before: before.total, after: after.total } : null,
    balanceAfter: after,
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
  lines.push(`**${formatCostLine(report.cost)}**`);
  const elements: Record<string, unknown>[] = [
    { tag: "div", text: { tag: "lark_md", content: lines.join("\n") } },
  ];
  const warn = lowBalanceWarning(report.balanceAfter);
  if (warn) elements.push({ tag: "div", text: { tag: "lark_md", content: warn } });
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

/** 统一发送器（非抛）：未配置 webhook / 该阶段已发 → 跳过；发送成功才记账。
 * 卡片与成功日志明细都惰性构造（未配置时不做无用功）。 */
async function notifyOnce(
  ctx: FeishuNotifyCtx,
  phase: NotifyPhase,
  runDate: string,
  label: string,
  build: () => { card: Record<string, unknown>; detail: string },
): Promise<void> {
  const { serverCfg } = ctx;
  if (!serverCfg.feishuWebhookUrl || !serverCfg.feishuWebhookSecret) {
    log(`[feishu-notify] ${runDate} 未配置 FEISHU_WEBHOOK_URL/FEISHU_WEBHOOK_SECRET，跳过${label}`);
    return;
  }
  const notified = ctx.notified ?? notifiedDates;
  const key = `${runDate}:${phase}`;
  if (notified.has(key)) {
    log(`[feishu-notify] ${runDate} ${label}已发送过，跳过（去重）`);
    return;
  }
  try {
    const { card, detail } = build();
    await sendFeishu(ctx, serverCfg.feishuWebhookUrl, serverCfg.feishuWebhookSecret, card);
    notified.add(key);
    log(`[feishu-notify] ${runDate} ${label}已发送${detail ? `（${detail}）` : ""}`);
  } catch (err) {
    log(
      `[feishu-notify] ${runDate} ${label}发送失败（不影响生成流程）: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

/** 开始卡（一次运行的第一条消息）：看到它却看不到结束卡 = 本次运行没跑完。 */
export function buildStartCard(args: DailyStartArgs, timeZone: string): Record<string, unknown> {
  const lines = [
    `**执行日期**：${args.runDate}（${timeZone}）`,
    `**开始**：${formatTime(args.startedAt, timeZone)}`,
    `**运行前余额**：${formatBalance(args.balanceBefore)}`,
  ];
  const elements: Record<string, unknown>[] = [
    { tag: "div", text: { tag: "lark_md", content: lines.join("\n") } },
  ];
  const warn = lowBalanceWarning(args.balanceBefore);
  if (warn) elements.push({ tag: "div", text: { tag: "lark_md", content: warn } });
  return {
    config: { wide_screen_mode: true },
    header: { template: "blue", title: { tag: "plain_text", content: `🚀 每日生成开始 · ${args.runDate}` } },
    elements,
  };
}

/** 未收口告警卡（看门狗触发）：窗口结束仍未收口 → 明确"有开始没结束"。 */
export function buildAlertCard(args: DailyAlertArgs, timeZone: string): Record<string, unknown> {
  const reason =
    args.batchStatus === "none"
      ? "当天批次不存在（生成从未开始，或批次已被清理）"
      : `当天批次仍未收口（status=${args.batchStatus}）`;
  const lines = [
    `**执行日期**：${args.runDate}（${timeZone}）`,
    `**检查时刻**：${formatTime(args.checkedAt, timeZone)}`,
    `**状态**：${reason}`,
  ];
  const elements: Record<string, unknown>[] = [
    { tag: "div", text: { tag: "lark_md", content: lines.join("\n") } },
    { tag: "hr" },
    {
      tag: "div",
      text: {
        tag: "lark_md",
        content:
          "本告警由**独立看门狗**发出（不依赖生成循环是否活着）。若收到开始卡却没收到结束卡，即为本次生成卡死——请检查服务器。",
      },
    },
  ];
  return {
    config: { wide_screen_mode: true },
    header: { template: "orange", title: { tag: "plain_text", content: `⚠️ 每日生成未收口 · ${args.runDate}` } },
    elements,
  };
}

/**
 * 余额复核卡（延迟结算兜底）：结束卡本次成本为 0（余额未变，多为 DeepSeek 计费约 5 分钟
 * 延迟）→ 10 分钟后重查余额的结果。复核余额相对"运行前余额"折算真实成本。
 */
export function buildRecheckCard(args: DailyRecheckArgs, timeZone: string): Record<string, unknown> {
  const lines = [
    `**执行日期**：${args.runDate}（${timeZone}）`,
    `**结束卡**：${formatCostLine({
      currency: args.balanceAfter.currency,
      before: args.balanceBefore.total,
      after: args.balanceAfter.total,
    })}`,
    `**复核时刻**：${formatTime(args.checkedAt, timeZone)}`,
    `**复核结果**：${formatRecheckLine(args.balanceBefore, args.balanceSettled)}`,
  ];
  const elements: Record<string, unknown>[] = [
    { tag: "div", text: { tag: "lark_md", content: lines.join("\n") } },
  ];
  const warn = lowBalanceWarning(args.balanceSettled);
  if (warn) elements.push({ tag: "div", text: { tag: "lark_md", content: warn } });
  return {
    config: { wide_screen_mode: true },
    header: { template: "blue", title: { tag: "plain_text", content: `💴 余额复核 · ${args.runDate}` } },
    elements,
  };
}

/** 复核结果行：以运行前余额为基准折算真实成本（复核失败/仍未变/增加分别如实标注）。 */
export function formatRecheckLine(before: BalanceSnapshot, settled: BalanceSnapshot | null): string {
  if (settled === null) return "余额查询失败——本次成本仍未结算，可稍后手动核对";
  const p = currencyPrefix(before.currency);
  const b = before.total.toFixed(2);
  const s = settled.total.toFixed(2);
  if (settled.total < before.total) return `本次成本 ≈ ${p}${(before.total - settled.total).toFixed(2)}（运行前 ${b} → 复核 ${s}）`;
  if (settled.total === before.total) return `余额仍未变化（${b}）——本次确实未产生消耗，或结算延迟更久`;
  return `余额增加（${b} → ${s}，多为充值）——本次成本仍未结算`;
}

/** 开始卡发送（非抛）。 */
export async function notifyDailyStart(ctx: FeishuNotifyCtx, args: DailyStartArgs): Promise<void> {
  await notifyOnce(ctx, "start", args.runDate, "开始通知", () => ({
    card: buildStartCard(args, ctx.engineCfg.timezone),
    detail: "",
  }));
}

/** 余额复核发送（非抛）；由 cost_recheck 在结束卡 10 分钟后调用。 */
export async function notifyDailyCostRecheck(ctx: FeishuNotifyCtx, args: DailyRecheckArgs): Promise<void> {
  await notifyOnce(ctx, "recheck", args.runDate, "余额复核通知", () => ({
    card: buildRecheckCard(args, ctx.engineCfg.timezone),
    detail: `复核余额 ${formatBalance(args.balanceSettled)}`,
  }));
}

/** 未收口告警发送（非抛）。 */
export async function notifyDailyUnclosed(ctx: FeishuNotifyCtx, args: DailyAlertArgs): Promise<void> {
  await notifyOnce(ctx, "alert", args.runDate, "未收口告警", () => ({
    card: buildAlertCard(args, ctx.engineCfg.timezone),
    detail: `批次状态 ${args.batchStatus}`,
  }));
}

/** 余额渲染（null = 查询失败）。 */
export function formatBalance(b: BalanceSnapshot | null): string {
  return b === null ? "查询失败" : `${currencyPrefix(b.currency)}${b.total.toFixed(2)}`;
}

/**
 * 本次成本行。余额差是唯一口径：下降 = 成本；未变 = 计费延迟（约 5 分钟）尚未结算，
 * 不假装本次免费；上升多为运行期间充值；余额未知则如实标"未知"。
 */
export function formatCostLine(cost: DailyCost | null): string {
  if (cost === null) return "本次成本：未知（余额查询失败）";
  const p = currencyPrefix(cost.currency);
  const before = cost.before.toFixed(2);
  const after = cost.after.toFixed(2);
  if (cost.after > cost.before) return `本次成本：—（余额增加 ${before} → ${after}，多为充值）`;
  if (cost.after === cost.before) {
    return `本次成本 ≈ ${p}0.00（${before} → ${after}，计费约 5 分钟延迟尚未结算）`;
  }
  return `本次成本 ≈ ${p}${(cost.before - cost.after).toFixed(2)}（${before} → ${after}）`;
}

/** 低余额提醒文案；未低/未知 → null（查询失败不误报）。 */
export function lowBalanceWarning(b: BalanceSnapshot | null): string | null {
  if (b === null || !isLowBalance(b)) return null;
  return `⚠️ 余额不足 ${currencyPrefix(b.currency)}${LOW_BALANCE_THRESHOLD}（当前 ${formatBalance(b)}），请立即充值`;
}

/** 货币前缀：CNY → ¥，其余用币种代码（避免给非人民币账户标错符号）。 */
function currencyPrefix(currency: string): string {
  return currency === "CNY" ? "¥" : `${currency} `;
}

/**
 * 每日运行结束后的通知入口（非抛）：未配置 webhook / 当日已发 → 跳过；
 * 发送成功才记账。任何失败仅记日志（通知不得中断生成流程）。
 */
export async function notifyDailyResult(ctx: FeishuNotifyCtx, args: DailyNotifyArgs): Promise<void> {
  await notifyOnce(ctx, "end", args.runDate, "结束通知", () => {
    const report = buildDailyReport(ctx.db, args, ctx.engineCfg.timezone);
    return {
      card: buildDailyCard(report),
      detail: `成功 ${report.success}/${report.totalSlots}，失败 ${report.error + report.rejected}`,
    };
  });
}
