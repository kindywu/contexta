// src/services/daily_task.ts
// 每日任务编排（对齐旧 Rust tasks/article_daily_task.rs 语义，时序见架构文档 §5.2）：
// - startupFill：启动补漏——生成今天 + 明天（同一次 now() 推导，防跨午夜）；失败仅记日志
// - loop：无限循环——睡到 DAILY_GENERATE_HOUR:01（分钟=01 避整点边界；服务器本地 =
//   配置时区，assertSystemTimezone 保证）→ 补今天（幂等、成本为零）+ 主生成明天；
//   单轮失败已由 runFill 内部日志化，循环继续
// - runFill：引擎幂等生成（无批次→建 15 槽全跑；running→只补 pending；已收口→直接返回）
//   → retryFailedSlots（pending 恢复：resume/sync）→ error 槽位每槽一次 retrySlot（图三态
//   承诺：补跑仍失败留 error，err 不抛）→ ensureReviewRows 补齐审核行
// - runFill in-flight 去重（模块级，按日期）：startupFill 与 loop 可能同日双调
//   （启动 + 03:01）→ 两连接同跑 pending 槽 = 双倍 LLM 成本 + 可能孤儿行；
//   并发调用返回同一 Promise（不双跑），失败兜底也已去重
// - 单步失败仅记日志（console.error），不中断后续步骤与整个 fill——旧版
//   "失败只记日志不阻止 serve" 语义
// - 槽位级去重：error 补跑与审核重生成共用 Task 7 的进程锁（同槽串行）
// 测试注入：genDaily/retryFailed/reRun/ensure/now/sleep 全部可替换（见 DailyTaskCtx）。
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { listSlots, type SlotRow } from "../engine/db";
import { generateDailyArticles, retryFailedSlots } from "../engine/graph/daily";
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

/**
 * 下一次触发（DAILY_GENERATE_HOUR:01）与 now 的毫秒差（测试可注入 now 后直接断言）。
 * 日期与时刻均按"系统时区 = 配置时区"（assertSystemTimezone 保证）用本地 Date 构造，
 * 与 Rust 版 `Local::now()` 口径一致：now.hour < hour → 今天该时刻，否则明天该时刻。
 */
export function nextTriggerWaitMs(now: Date, hour: number, timeZone: string): number {
  const todayTrigger = todayStartMillis(timeZone, now) + hour * 3_600_000 + 60_000; // 今日 hour:01
  const nextTrigger = now.getHours() < hour ? todayTrigger : todayTrigger + 86_400_000;
  return nextTrigger - now.getTime();
}

/** 模块级 in-flight 去重（按日期 → 进行中的 fill Promise）：startupFill 与 loop
 * 双后台任务可能同日并发（启动补漏 + 03:01 定时）——同日期并发时返回同一 Promise，
 * 内层 genDaily/retryFailed/补跑只执行一次（不双跑）。settled（含失败）即删除条目。 */
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
   * in-flight 去重：同一日期并发调用（startupFill 与 loop 双后台）返回同一
   * Promise——双跑同一日期 = 双倍 LLM 成本 + 并发写同槽位。
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
      console.error(`[daily-task] ${date} 引擎生成失败（继续后续步骤）:`, err);
    }
    try {
      await this.retryFailed({ runDate: date, config: this.ctx.engineCfg });
    } catch (err) {
      console.error(`[daily-task] ${date} pending 恢复失败（继续后续步骤）:`, err);
    }
    try {
      for (const slot of listSlots(this.ctx.db, date)) {
        if (slot.status !== "error") continue;
        try {
          await this.reRun(this.ctx, slot);
        } catch (err) {
          console.error(`[daily-task] ${date} slot ${slot.id}[${slot.slotIndex}] 补跑失败（留 error）:`, err);
        }
      }
    } catch (err) {
      console.error(`[daily-task] ${date} 列槽失败:`, err);
    }
    try {
      this.ensure(this.ctx.db);
    } catch (err) {
      console.error(`[daily-task] ${date} 审核行补齐失败:`, err);
    }
  }

  /** 启动补漏：今天 + 明天（同一次 now() 推导防跨午夜）；单日失败仅记日志。 */
  async startupFill(): Promise<void> {
    const now = this.now();
    const today = localDate(this.ctx.engineCfg.timezone, now);
    const tomorrow = localDate(this.ctx.engineCfg.timezone, new Date(now.getTime() + 86_400_000));
    for (const date of [today, tomorrow]) {
      try {
        await this.runFill(date);
      } catch (err) {
        console.error(`[daily-task] startupFill ${date} 失败:`, err);
      }
    }
  }

  /**
   * 每日定时循环（无限）：睡到 DAILY_GENERATE_HOUR:01 → 补今天（幂等、成本为零）+
   * 主生成明天；触发后等待本轮 fill 完成了才进入下一次 sleep。今天/明天由同一次
   * now() 推导。fill 失败已内部日志化（循环继续）；sleep 异常向调用方传播
   * （Bun.sleep 生产不抛；测试用假 sleep 抛错终止循环）。
   */
  async loop(): Promise<void> {
    for (;;) {
      const hour = this.ctx.serverCfg.dailyGenerateHour;
      const wait = nextTriggerWaitMs(this.now(), hour, this.ctx.engineCfg.timezone);
      console.log(`[daily-task] 下一次生成于 ${hour}:01，等待 ${Math.max(0, Math.round(wait / 1000))}s`);
      await this.sleep(wait);
      const now = this.now();
      const today = localDate(this.ctx.engineCfg.timezone, now);
      const tomorrow = localDate(this.ctx.engineCfg.timezone, new Date(now.getTime() + 86_400_000));
      await this.runFill(today); // 补：启动补漏失败后当天缺文自愈
      await this.runFill(tomorrow); // 主生成
    }
  }

  /**
   * 启动两个后台任务（Bun 无 tokio spawn——void promise 风格；服务进程退出即结束）。
   * 两个任务各自兜底 catch（startupFill/loop 内部已日志化，此处只兜计划外异常）。
   */
  start(): void {
    void this.startupFill().catch((err) => console.error("[daily-task] 启动补漏后台异常:", err));
    void this.loop().catch((err) => console.error("[daily-task] 定时循环后台异常:", err));
  }
}
