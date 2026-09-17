// src/services/run_report.ts
// 一次"整日运行"的上报包装（唯一实现，供每日定时与管理端手动补生成共用）：
//   查余额（运行前）→ 发开始卡 → 跑 → 查余额（运行后）→ 发结束卡（含本次成本）
//   →（成本为 0 时）排一次延迟余额复核
// - 结束卡在运行抛错时也发（stepErrors 记录抛错）再向上重抛——保证"有开始必有结束"这条
//   判定链完整：只有真卡死才会出现"有开始没结束"
// - 结束卡成本为 0（余额未变）时排延迟复核：DeepSeek 计费约 5 分钟延迟，结束卡时可能尚未
//   结算——10 分钟后重查余额再发一条复核消息（见 cost_recheck），不阻塞运行
// - 纪律：通知/余额查询/复核调度任何异常都只记日志，绝不中断运行——通知故障不得变成生成故障
//   （余额查询同理，见 llm_balance 的 null 兜底）
import { log } from "../engine/graph/log";
import { isZeroCost, recheckCost, type CostRecheckArgs } from "./cost_recheck";
import {
  notifyDailyResult,
  notifyDailyStart,
  type DailyNotifyArgs,
  type DailyStartArgs,
  type FeishuNotifyCtx,
} from "./feishu_notify";
import { fetchBalance, type BalanceCtx, type BalanceSnapshot } from "./llm_balance";

/** 上报上下文：飞书上下文 + 余额上下文 + 测试 seam。 */
export interface RunReportCtx extends FeishuNotifyCtx {
  balance: BalanceCtx;
  /** 余额查询 seam（缺省 fetchBalance） */
  probe?: (ctx: BalanceCtx) => Promise<BalanceSnapshot | null>;
  /** 开始卡 seam（缺省 notifyDailyStart） */
  notifyStart?: (ctx: FeishuNotifyCtx, args: DailyStartArgs) => Promise<void>;
  /** 结束卡 seam（缺省 notifyDailyResult） */
  notifyEnd?: (ctx: FeishuNotifyCtx, args: DailyNotifyArgs) => Promise<void>;
  /** 成本复核调度 seam（缺省 = 以同一批 seam 排一次 cost_recheck.recheckCost） */
  recheck?: (args: CostRecheckArgs) => void;
}

/** 包装结果：起止时刻 + 运行步骤错误（供调用方组装自己的返回口径）。 */
export interface RunReportOutcome {
  startedAt: Date;
  endedAt: Date;
  stepErrors: string[];
}

/** 上报 seam：调用方（daily_task / admin）注入假实现即可不碰余额与飞书。 */
export type RunReportFn = (
  runDate: string,
  run: () => Promise<{ stepErrors: string[] }>,
) => Promise<RunReportOutcome>;

/** 构造缺省上报函数（真实余额查询 + 真实飞书；配置从两份 cfg 取）。 */
export function defaultRunReport(db: FeishuNotifyCtx["db"], serverCfg: FeishuNotifyCtx["serverCfg"], engineCfg: FeishuNotifyCtx["engineCfg"]): RunReportFn {
  return (runDate, run) =>
    withDailyRunReport(
      {
        db,
        serverCfg,
        engineCfg,
        balance: { baseUrl: engineCfg.llmBaseUrl, apiKey: engineCfg.llmApiKey },
      },
      runDate,
      run,
    );
}

/** 包住一次整日运行：开始卡 → run → 结束卡（成本 = 前后余额差）。 */
export async function withDailyRunReport(
  ctx: RunReportCtx,
  runDate: string,
  run: () => Promise<{ stepErrors: string[] }>,
): Promise<RunReportOutcome> {
  const now = ctx.now ?? (() => new Date());
  const probe = ctx.probe ?? fetchBalance;
  const notifyStart = ctx.notifyStart ?? notifyDailyStart;
  const notifyEnd = ctx.notifyEnd ?? notifyDailyResult;
  // 复核调度（fire-and-forget）：同一批 seam（probe/now/fetch/notified）传给复核链——
  // 测试注入的假余额/假时钟对复核同样生效
  const recheck =
    ctx.recheck ??
    ((args: CostRecheckArgs) => {
      void recheckCost(
        {
          db: ctx.db,
          serverCfg: ctx.serverCfg,
          engineCfg: ctx.engineCfg,
          balance: ctx.balance,
          fetch: ctx.fetch,
          now: ctx.now,
          notified: ctx.notified,
          probe,
        },
        args,
      );
    });

  const startedAt = now();
  const balanceBefore = await probe(ctx.balance);
  await safeNotify(`开始卡 ${runDate}`, () => notifyStart(ctx, { runDate, startedAt, balanceBefore }));

  let stepErrors: string[];
  let endedAt: Date;
  try {
    stepErrors = (await run()).stepErrors;
    endedAt = now();
  } catch (err) {
    endedAt = now();
    const balanceAfter = await probe(ctx.balance);
    await safeNotify(`结束卡 ${runDate}`, () =>
      notifyEnd(ctx, {
        runDate,
        startedAt,
        endedAt,
        balanceBefore,
        balanceAfter,
        stepErrors: [`引擎生成抛错: ${err instanceof Error ? err.message : String(err)}`],
      }),
    );
    maybeScheduleRecheck(recheck, runDate, balanceBefore, balanceAfter);
    throw err;
  }

  const balanceAfter = await probe(ctx.balance);
  await safeNotify(`结束卡 ${runDate}`, () =>
    notifyEnd(ctx, { runDate, startedAt, endedAt, balanceBefore, balanceAfter, stepErrors }),
  );
  maybeScheduleRecheck(recheck, runDate, balanceBefore, balanceAfter);
  return { startedAt, endedAt, stepErrors };
}

/** 成本为 0（两侧余额都查到且相等）→ 排一次延迟复核；调度异常只记日志（不影响运行）。 */
function maybeScheduleRecheck(
  recheck: (args: CostRecheckArgs) => void,
  runDate: string,
  balanceBefore: BalanceSnapshot | null,
  balanceAfter: BalanceSnapshot | null,
): void {
  if (balanceBefore === null || balanceAfter === null) return;
  if (!isZeroCost(balanceBefore, balanceAfter)) return;
  try {
    recheck({ runDate, balanceBefore, balanceAfter });
  } catch (err) {
    log(`[run-report] ${runDate} 成本复核调度异常（不影响运行）: ${err instanceof Error ? err.message : String(err)}`);
  }
}

/** 通知调用兜底：seam 自身已是非抛的，这里再加一层——通知永不影响运行。 */
async function safeNotify(label: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
  } catch (err) {
    log(`[run-report] ${label} 发送异常（不影响运行）: ${err instanceof Error ? err.message : String(err)}`);
  }
}
