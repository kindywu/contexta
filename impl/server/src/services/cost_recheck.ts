// src/services/cost_recheck.ts
// 成本复核（延迟结算兜底）：结束卡"本次成本 ≈ 0"多半不是真的没花钱，而是 DeepSeek 计费
// 约 5 分钟延迟、结束卡查余额时尚未结算——结束卡发出后 RECHECK_DELAY_MS（10 分钟）再查
// 一次余额，把真实成本补一条飞书消息（卡片渲染见 feishu_notify.notifyDailyCostRecheck）。
// - 排复核的前置判定在调用方（run_report 的 isZeroCost：两侧余额都查到且相等）——余额未知
//   （查询失败）不算 0，不排
// - 纪律同 run_report：复核是 fire-and-forget 的独立 async 链——不阻塞运行（每日循环与
//   管理端响应都不等它），任何失败（sleep/probe/notify）只记日志绝不抛
// - 进程内一次性、不落库：进程若在 10 分钟窗口内重启，该次复核丢失（服务长驻，接受）
// - 不递归：复核后余额仍未变不再排第二次——"确实未消耗 / 结算更久"如实标注即可
import { log } from "../engine/graph/log";
import { notifyDailyCostRecheck, type DailyRecheckArgs, type FeishuNotifyCtx } from "./feishu_notify";
import { fetchBalance, type BalanceCtx, type BalanceSnapshot } from "./llm_balance";

/** 复核延迟：结束卡发出后到此才再查余额（DeepSeek 计费约 5 分钟延迟，10 分钟留余量）。 */
export const RECHECK_DELAY_MS = 10 * 60_000;

/** 成本为 0 判定：两侧余额都查到且相等；任一未知（null）不算 0。 */
export function isZeroCost(before: BalanceSnapshot | null, after: BalanceSnapshot | null): boolean {
  return before !== null && after !== null && before.total === after.total;
}

/** 一次复核的入参（结束卡时刻的两个余额快照）。 */
export interface CostRecheckArgs {
  runDate: string;
  /** 结束卡时的运行前余额 */
  balanceBefore: BalanceSnapshot;
  /** 结束卡时的运行后余额（与 before 相等 = 排此复核的原因） */
  balanceAfter: BalanceSnapshot;
}

/** 复核上下文：飞书通知上下文 + 余额上下文 + 测试 seam。 */
export interface CostRecheckCtx extends FeishuNotifyCtx {
  balance: BalanceCtx;
  /** 余额查询 seam（缺省 fetchBalance） */
  probe?: (ctx: BalanceCtx) => Promise<BalanceSnapshot | null>;
  /** 复核卡 seam（缺省 notifyDailyCostRecheck） */
  notify?: (ctx: FeishuNotifyCtx, args: DailyRecheckArgs) => Promise<void>;
  /** 定时器 seam（缺省 Bun.sleep；测试注入假实现） */
  sleep?: (ms: number) => Promise<void>;
}

/**
 * 延迟复核一次（非抛，调用方以 `void` 方式 fire-and-forget）：
 * 睡 RECHECK_DELAY_MS → 查余额 → 发复核卡。任何异常只记日志——复核故障绝不影响运行。
 */
export async function recheckCost(ctx: CostRecheckCtx, args: CostRecheckArgs): Promise<void> {
  const sleep = ctx.sleep ?? ((ms: number) => Bun.sleep(ms));
  const probe = ctx.probe ?? fetchBalance;
  const notify = ctx.notify ?? notifyDailyCostRecheck;
  try {
    log(`[cost-recheck] ${args.runDate} 结束卡成本为 0，${Math.round(RECHECK_DELAY_MS / 60_000)} 分钟后复核余额`);
    await sleep(RECHECK_DELAY_MS);
    const balanceSettled = await probe(ctx.balance);
    const checkedAt = (ctx.now ?? (() => new Date()))();
    await notify(ctx, {
      runDate: args.runDate,
      checkedAt,
      balanceBefore: args.balanceBefore,
      balanceAfter: args.balanceAfter,
      balanceSettled,
    });
  } catch (err) {
    log(`[cost-recheck] ${args.runDate} 复核异常（不影响运行）: ${err instanceof Error ? err.message : String(err)}`);
  }
}
