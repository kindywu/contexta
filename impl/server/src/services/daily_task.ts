// src/services/daily_task.ts
// 每日任务编排（窗口触发语义：每天生成窗口内只生成"当天"15 篇；错过窗口跳过，不补不重试）：
// - loop：无限循环——不在窗口内 → 睡到下一窗口开始（已过窗口 = 当天错过，直接等明天）；
//   进入窗口 → 三态判定当天批次：已收口（status != running）→ 跳过；无批次/执行中 → runFill
//   （引擎幂等：无批次→建 15 槽全跑；running→只补 pending 后收口）
// - runFill：引擎生成 → retryFailedSlots（pending 恢复：resume/sync）→ error 槽位每槽一次
//   retrySlot（图三态承诺：补跑仍失败留 error，err 不抛）→ ensureReviewRows 补齐审核行
// - runFill in-flight 去重（模块级，按日期）：并发调用返回同一 Promise（不双跑），
//   失败兜底也已去重
// - 单步失败仅记日志（走引擎 log() → logs/daily-<date>.log，服务进程内不输出到 web stdout；
//   CLI 场景 console 保留），不中断后续步骤与整个 fill
// - 槽位级去重：error 补跑与审核重生成共用 Task 7 的进程锁（同槽串行）
// 测试注入：genDaily/retryFailed/reRun/ensure/now/sleep 全部可替换（见 DailyTaskCtx）。
import type { Database } from "bun:sqlite";
import { DEFAULT_LOG_DIR, formatWindow, type DailyWindow, type ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { isDailyBatchFinished, listSlots, type SlotRow } from "../engine/db";
import { generateDailyArticles, retryFailedSlots } from "../engine/graph/daily";
import { cleanupOldLogs, log } from "../engine/graph/log";
import { localDate } from "../engine/utils/time";
import { todayStartMillis } from "../time";
import { ensureReviewRows, retrySlot, type GenFn } from "./review_service";

/** 每日生成/重试 seam 入参（引擎 generateDailyArticles / retryFailedSlots 的子集）。 */
export interface DailyGenArgs {
  runDate: string;
  config: AppConfig;
}

/** 每日生成/重试 seam（缺省 = 引擎 generateDailyArticles / retryFailedSlots 闭包）。 */
export type DailyGenFn = (args: DailyGenArgs) => Promise<unknown>;

/** error 槽补跑 seam（缺省 = review_service.retrySlot）。 */
export type DailyReRunFn = (ctx: DailyTaskCtx, slotRow: SlotRow) => Promise<void>;

/**
 * 每日任务上下文：db = 服务端共享连接；engineCfg/serverCfg 为配置；
 * 其余为注入 seam——测试注入假实现，缺省接引擎与审核服务。
 */
export interface DailyTaskCtx {
  db: Database;
  engineCfg: AppConfig;
  serverCfg: ServerConfig;
  /** 引擎生成（幂等）：缺省 generateDailyArticles 闭包 */
  genDaily?: DailyGenFn;
  /** 引擎 pending 恢复（resume/sync）：缺省 retryFailedSlots 闭包 */
  retryFailed?: DailyGenFn;
  /**
   * error 槽补跑：缺省 review_service.retrySlot——R4 唯一 genSeq（thread =
   * daily-<date>-<slot>-r<Date.now()>）：恒定 -r1 会命中引擎"同 threadId 终态
   * checkpoint 复用"契约，第二次补跑/审核首次拒绝静默 no-op（05ad9be 同 bug 类）。
   */
  reRun?: DailyReRunFn;
  /**
   * 槽位级生成（仅经缺省 reRun → retrySlot → reRunSlot 消费；reRunSlot 的 ctx 是
   * DailyTaskCtx 本身，ctx.gen ?? 引擎 generateArticle）：测试注入 error 三态假实现，
   * 使缺省补跑路径可端到端验证且不真调引擎/LLM。
   */
  gen?: GenFn;
  /** 审核行补齐：缺省 review_service.ensureReviewRows */
  ensure?: typeof ensureReviewRows;
  /** 时钟注入：缺省 new Date（测试固定时刻） */
  now?: () => Date;
  /** 定时器注入：缺省 Bun.sleep（测试假 sleep 不真等） */
  sleep?: (ms: number) => Promise<void>;
}

/** 每日生成窗口（配置时区当日）：now 是否落在 [start, end] 闭区间内。 */
export function isInDailyWindow(now: Date, window: DailyWindow, timeZone: string): boolean {
  const dayStart = todayStartMillis(timeZone, now);
  const s = dayStart + window.start * 60_000;
  const e = dayStart + window.end * 60_000;
  return now.getTime() >= s && now.getTime() <= e;
}

/**
 * 距下一窗口开始的毫秒：now < 今日窗口开始 → 今日窗口；否则（窗口内/已过）→ 明日窗口。
 * 窗口内时刻调用此函数即得到"下一轮"＝明日窗口——loop 触发处理后用它睡过当日窗口，
 * 避免窗口内立即重复触发（如 08:00 跳过批次后不会在 08:15 前空转重查）。
 */
export function nextTriggerWaitMs(now: Date, window: DailyWindow, timeZone: string): number {
  const dayStart = todayStartMillis(timeZone, now);
  const s = dayStart + window.start * 60_000;
  return now.getTime() < s ? s - now.getTime() : s + 86_400_000 - now.getTime();
}

/** 模块级 in-flight 去重（按日期 → 进行中的 fill Promise）：并发可能同日双调
 * （loop 与手动入口）→ 同日期并发时返回同一 Promise，内层 genDaily/retryFailed/
 * 补跑只执行一次（不双跑）。settled（含失败）即删除条目。 */
const fillInflight = new Map<string, Promise<void>>();

/** 每日任务（main 组装时经 start() 后台启动；服务进程退出即结束）。 */
export class DailyTask {
  private readonly ctx: DailyTaskCtx;
  private readonly genDaily: DailyGenFn;
  private readonly retryFailed: DailyGenFn;
  private readonly reRun: DailyReRunFn;
  private readonly ensure: typeof ensureReviewRows;
  private readonly now: () => Date;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(ctx: DailyTaskCtx) {
    this.ctx = ctx;
    this.genDaily =
      ctx.genDaily ?? ((args) => generateDailyArticles({ runDate: args.runDate, config: args.config }));
    this.retryFailed =
      ctx.retryFailed ?? ((args) => retryFailedSlots({ runDate: args.runDate, config: args.config }));
    this.reRun = ctx.reRun ?? ((c, s) => retrySlot(c, s));
    this.ensure = ctx.ensure ?? ensureReviewRows;
    this.now = ctx.now ?? (() => new Date());
    this.sleep = ctx.sleep ?? ((ms) => Bun.sleep(ms));
  }

  /**
   * 单日填充（幂等）：引擎生成 → pending 恢复 → error 槽每槽一次补跑 → 审核行补齐。
   * 单步失败仅记日志（不中断后续步骤）；补跑仍失败留 error——err 不抛。
   * in-flight 去重：同一日期并发调用返回同一 Promise——双跑同一日期 = 双倍 LLM
   * 成本 + 并发写同槽位。
   */
  runFill(date: string): Promise<void> {
    const existing = fillInflight.get(date);
    if (existing) return existing;
    const fill = this.runFillInner(date).finally(() => fillInflight.delete(date));
    fillInflight.set(date, fill);
    return fill;
  }

  private async runFillInner(date: string): Promise<void> {
    try {
      await this.genDaily({ runDate: date, config: this.ctx.engineCfg });
    } catch (err) {
      log(`[daily-task] ${date} 引擎生成失败（继续后续步骤）: ${errText(err)}`);
    }
    try {
      await this.retryFailed({ runDate: date, config: this.ctx.engineCfg });
    } catch (err) {
      log(`[daily-task] ${date} pending 恢复失败（继续后续步骤）: ${errText(err)}`);
    }
    try {
      for (const slot of listSlots(this.ctx.db, date)) {
        if (slot.status !== "error") continue;
        try {
          await this.reRun(this.ctx, slot);
        } catch (err) {
          log(`[daily-task] ${date} slot ${slot.id}[${slot.slotIndex}] 补跑失败（留 error）: ${errText(err)}`);
        }
      }
    } catch (err) {
      log(`[daily-task] ${date} 列槽失败: ${errText(err)}`);
    }
    try {
      this.ensure(this.ctx.db);
    } catch (err) {
      log(`[daily-task] ${date} 审核行补齐失败: ${errText(err)}`);
    }
  }

  /**
   * 每日窗口循环（无限）：不在窗口（未到/已过）→ 睡到下一窗口开始（已过 = 当天错过，
   * 直接等明天，不补不重试）；进入窗口 → 三态判定当天（收口跳过 / 无批次或 running 则
   * runFill）→ 清理 7 天前旧日志 → 睡到明日窗口。窗口与日期口径：配置时区（localDate）。
   * runFill 失败已内部日志化（循环继续）；sleep 异常向调用方传播（Bun.sleep 生产不抛；
   * 测试用假 sleep 抛错终止循环）。
   */
  async loop(): Promise<void> {
    for (;;) {
      const w = this.ctx.serverCfg.dailyGenerateWindow;
      const tz = this.ctx.engineCfg.timezone;
      const now = this.now();
      if (!isInDailyWindow(now, w, tz)) {
        const wait = nextTriggerWaitMs(now, w, tz);
        log(`[daily-task] 下一次生成窗口 ${formatWindow(w)}，等待 ${Math.max(0, Math.round(wait / 1000))}s`);
        await this.sleep(wait);
        continue;
      }
      // 窗口内：只处理"今天"（触发时刻当天）；错过/收口均不再触碰
      const date = localDate(tz, this.now());
      if (isDailyBatchFinished(this.ctx.db, date)) {
        log(`[daily-task] ${date} 批次已收口，跳过本轮生成`);
      } else {
        await this.runFill(date);
      }
      cleanupOldLogs(DEFAULT_LOG_DIR, 7, tz); // 每日一次：清理 7 天前的旧日志
      await this.sleep(nextTriggerWaitMs(this.now(), w, tz)); // 睡到明日窗口（见函数注释）
    }
  }

  /** 启动后台任务（Bun 无 tokio spawn——void promise 风格；服务进程退出即结束）。
   * 启动不生成文章：只跑窗口循环，窗口错过即跳过。 */
  start(): void {
    void this.loop().catch((err) => log(`[daily-task] 定时循环后台异常: ${errText(err)}`));
  }
}

function errText(err: unknown): string {
  return err instanceof Error ? (err.stack ?? err.message) : String(err);
}
