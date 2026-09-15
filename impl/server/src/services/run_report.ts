// src/services/run_report.ts
// 一次"整日运行"的上报包装（唯一实现，供每日定时与管理端手动补生成共用）：
//   查余额（运行前）→ 发开始卡 → 跑 → 查余额（运行后）→ 发结束卡（含本次成本）
// - 结束卡在运行抛错时也发（stepErrors 记录抛错）再向上重抛——保证"有开始必有结束"这条
//   判定链完整：只有真卡死才会出现"有开始没结束"
// - 纪律：通知环节任何异常都只记日志，绝不中断运行——通知故障不得变成生成故障
//   （余额查询同理，见 llm_balance 的 null 兜底）
import { log } from "../engine/graph/log";
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
    throw err;
  }

  const balanceAfter = await probe(ctx.balance);
  await safeNotify(`结束卡 ${runDate}`, () =>
    notifyEnd(ctx, { runDate, startedAt, endedAt, balanceBefore, balanceAfter, stepErrors }),
  );
  return { startedAt, endedAt, stepErrors };
}

/** 通知调用兜底：seam 自身已是非抛的，这里再加一层——通知永不影响运行。 */
async function safeNotify(label: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
  } catch (err) {
    log(`[run-report] ${label} 发送异常（不影响运行）: ${err instanceof Error ? err.message : String(err)}`);
  }
}
