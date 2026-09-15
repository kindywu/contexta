// src/services/daily_alert.ts
// 未收口看门狗：每日窗口结束 + 60 分钟后检查"当天批次"，不存在或仍 running → 发飞书告警。
// 存在意义（2026-09-12 事故教训）：每日生成循环是 `await runFill`，抓取层一旦永久挂起，
// 循环与通知一起静默——三天无人知。本看门狗是**独立于生成循环的第二条 async 链**：
// 主循环卡死时事件循环仍健康，它照样跑得出告警（"有开始没结束"的自动判定）。
// - 只告警，不自动重启/不补跑（恢复仍由人工决定）
// - 按日去重；进程重启后若已过检查点会立即补查一次（重启当天即能得到告警）
// - 任何异常只记日志：看门狗自己绝不允许死掉
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { getBatch, isDailyBatchFinished } from "../engine/db";
import { log } from "../engine/graph/log";
import { localDate } from "../engine/utils/time";
import { todayStartMillis } from "../time";
import { notifyDailyUnclosed, type DailyAlertArgs, type FeishuNotifyCtx } from "./feishu_notify";

/** 窗口结束后的宽限期（分钟）：正常一轮约 3 分钟，60 分钟足以排除"只是慢"。 */
export const ALERT_GRACE_MINUTES = 60;

/** 看门狗上下文（now/sleep/notify 为测试 seam）。 */
export interface DailyAlertCtx {
  db: Database;
  serverCfg: ServerConfig;
  engineCfg: AppConfig;
  /** 告警发送 seam（缺省 notifyDailyUnclosed） */
  notify?: (ctx: FeishuNotifyCtx, args: DailyAlertArgs) => Promise<void>;
  /** 时钟 seam（缺省 new Date） */
  now?: () => Date;
  /** 定时器 seam（缺省 Bun.sleep） */
  sleep?: (ms: number) => Promise<void>;
  /** 按日去重集合 seam（缺省模块级集合） */
  notified?: Set<string>;
}

/** 模块级按日去重（进程生命周期内每天只告警一次）。 */
const alertedDates = new Set<string>();

/** 某天的检查时刻（毫秒）：配置时区当天零点 + 窗口结束 + 宽限期。 */
export function alertAtMillis(now: Date, windowEndMinutes: number, timeZone: string): number {
  return todayStartMillis(timeZone, now) + (windowEndMinutes + ALERT_GRACE_MINUTES) * 60_000;
}

/** 未收口看门狗（main 组装时与 DailyTask 一起后台启动）。 */
export class DailyAlertWatchdog {
  private readonly ctx: DailyAlertCtx;
  private readonly notifyCtx: FeishuNotifyCtx;
  private readonly notify: (ctx: FeishuNotifyCtx, args: DailyAlertArgs) => Promise<void>;
  private readonly now: () => Date;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(ctx: DailyAlertCtx) {
    this.ctx = ctx;
    this.notifyCtx = { db: ctx.db, serverCfg: ctx.serverCfg, engineCfg: ctx.engineCfg };
    this.notify = ctx.notify ?? notifyDailyUnclosed;
    this.now = ctx.now ?? (() => new Date());
    this.sleep = ctx.sleep ?? ((ms) => Bun.sleep(ms));
  }

  /**
   * 一次检查：未到检查点 / 当天已告警 / 批次已收口 → 不动；否则发告警。返回是否告警。
   * 检查口径与每日任务一致（配置时区当天）：无批次 = 当天生成从未开始（或批次被清理）。
   */
  async checkOnce(now: Date): Promise<boolean> {
    const w = this.ctx.serverCfg.dailyGenerateWindow;
    const tz = this.ctx.engineCfg.timezone;
    if (now.getTime() < alertAtMillis(now, w.end, tz)) return false;
    const date = localDate(tz, now);
    const notified = this.ctx.notified ?? alertedDates;
    if (notified.has(date)) return false;
    if (isDailyBatchFinished(this.ctx.db, date)) return false; // 已收口 = 正常结束
    const batchStatus = getBatch(this.ctx.db, date)?.status ?? "none";
    try {
      await this.notify(this.notifyCtx, { runDate: date, checkedAt: now, batchStatus });
      notified.add(date);
    } catch (err) {
      // 发送失败不记账（下次检查会重试），也不向外抛——看门狗必须活着
      log(`[daily-alert] ${date} 告警发送异常: ${err instanceof Error ? err.message : String(err)}`);
    }
    return true;
  }

  /** 无限循环：睡到当天检查点 → 检查 → 睡到明日检查点。异常不致命（记日志继续）。 */
  async loop(): Promise<void> {
    for (;;) {
      const w = this.ctx.serverCfg.dailyGenerateWindow;
      const tz = this.ctx.engineCfg.timezone;
      const now = this.now();
      const at = alertAtMillis(now, w.end, tz);
      if (now.getTime() < at) {
        await this.sleep(at - now.getTime());
        continue;
      }
      try {
        await this.checkOnce(this.now());
      } catch (err) {
        log(`[daily-alert] 检查异常（继续）: ${err instanceof Error ? err.message : String(err)}`);
      }
      await this.sleep(Math.max(0, at + 86_400_000 - this.now().getTime()));
    }
  }

  /** 启动后台看门狗（Bun 无 tokio spawn——void promise 风格；进程退出即结束）。 */
  start(): void {
    void this.loop().catch((err) =>
      log(`[daily-alert] 看门狗后台异常: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`),
    );
  }
}
