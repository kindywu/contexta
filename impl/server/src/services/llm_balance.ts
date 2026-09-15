// src/services/llm_balance.ts
// DeepSeek 账户余额查询（每日运行成本核算 + 低余额充值提醒的数据源）：
// - URL 由 LLM_BASE_URL 派生（<base>/user/balance），鉴权复用同一个 LLM_API_KEY
// - 金额是字符串（API 原样返回 "3.23"），此处统一转 number
// - 纪律：任何失败（网络/非 200/非 JSON/字段缺失/超时）一律返回 null——余额只服务通知，
//   绝不允许查询失败影响生成流程；调用方拿到 null 时按"未知"渲染（见 feishu_notify）
// - 计费延迟：DeepSeek 余额约 5 分钟后才反映消耗，运行后立刻取差可能为 0（渲染层标注）
import { log } from "../engine/graph/log";

/** 低余额告警阈值（元）：余额低于此值 → 通知里提醒充值。 */
export const LOW_BALANCE_THRESHOLD = 1;

/** 余额查询硬超时（毫秒）：接口卡住不得超过此预算。 */
const BALANCE_TIMEOUT_MS = 5000;

/** 一次余额快照（total 已转 number）。 */
export interface BalanceSnapshot {
  currency: string;
  total: number;
  at: Date;
}

/** 余额查询上下文（fetch/now 为测试 seam；baseUrl/apiKey 取自 LLM_BASE_URL / LLM_API_KEY）。 */
export interface BalanceCtx {
  baseUrl: string;
  apiKey: string;
  fetch?: typeof fetch;
  now?: () => Date;
}

/** 余额接口 URL：由 LLM_BASE_URL 派生（容忍尾斜杠）。 */
export function balanceUrl(baseUrl: string): string {
  return `${baseUrl.replace(/\/+$/, "")}/user/balance`;
}

/** 余额是否低于告警阈值；null（未知）不算低——查询失败不误报。 */
export function isLowBalance(b: BalanceSnapshot | null): boolean {
  return b !== null && b.total < LOW_BALANCE_THRESHOLD;
}

/** 查一次余额；任何失败返回 null（只记日志，不抛）。 */
export async function fetchBalance(ctx: BalanceCtx): Promise<BalanceSnapshot | null> {
  const at = (ctx.now ?? (() => new Date()))();
  try {
    const res = await (ctx.fetch ?? fetch)(balanceUrl(ctx.baseUrl), {
      headers: { Authorization: `Bearer ${ctx.apiKey}` },
      signal: AbortSignal.timeout(BALANCE_TIMEOUT_MS),
    });
    if (!res.ok) {
      log(`[balance] 余额查询失败: http=${res.status}`);
      return null;
    }
    const data = (await res.json()) as { balance_infos?: unknown };
    const infos = Array.isArray(data.balance_infos) ? data.balance_infos : [];
    const cny = infos.find((i) => (i as { currency?: unknown })?.currency === "CNY");
    const pick = (cny ?? infos[0]) as { currency?: unknown; total_balance?: unknown } | undefined;
    if (!pick) {
      log("[balance] 余额查询失败: balance_infos 为空");
      return null;
    }
    const raw = pick.total_balance;
    const total =
      typeof raw === "number" ? raw : typeof raw === "string" && raw.trim() !== "" ? Number(raw) : Number.NaN;
    if (!Number.isFinite(total)) {
      log(`[balance] 余额查询失败: total_balance 非法 (${String(raw)})`);
      return null;
    }
    return { currency: typeof pick.currency === "string" ? pick.currency : "CNY", total, at };
  } catch (err) {
    log(`[balance] 余额查询异常: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}
