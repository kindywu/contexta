// DeepSeek 余额查询（解析 / 币种选择 / 失败一律 null——绝不抛）：
// fetch 全注入假实现，不真发网络；金额是字符串（API 原样返回 "3.23"）必须转数字。
import { describe, expect, test } from "bun:test";
import {
  balanceUrl,
  fetchBalance,
  isLowBalance,
  LOW_BALANCE_THRESHOLD,
  type BalanceCtx,
  type BalanceSnapshot,
} from "../src/services/llm_balance";

const BASE = "https://api.deepseek.com";
const FIXED = new Date("2026-09-16T00:00:05Z");

/** fetch 假实现：返回给定 JSON（或原始文本）/ 状态码，并记录请求。 */
function fakeFetch(body: unknown, status = 200) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return new Response(typeof body === "string" ? body : JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  }) as unknown as typeof fetch;
  return { fn, calls };
}

function ctx(fetchFn: typeof fetch, baseUrl = BASE): BalanceCtx {
  return { baseUrl, apiKey: "sk-test", fetch: fetchFn, now: () => FIXED };
}

const cnyBody = {
  is_available: true,
  balance_infos: [
    { currency: "CNY", total_balance: "3.23", granted_balance: "0.00", topped_up_balance: "3.23" },
  ],
};

describe("balanceUrl（由 LLM_BASE_URL 派生）", () => {
  test("无尾斜杠 → 追加 /user/balance", () => {
    expect(balanceUrl(BASE)).toBe("https://api.deepseek.com/user/balance");
  });
  test("有尾斜杠 → 不产生双斜杠", () => {
    expect(balanceUrl("https://api.deepseek.com/")).toBe("https://api.deepseek.com/user/balance");
  });
});

describe("fetchBalance（解析与失败兜底）", () => {
  test("正常响应 → 金额字符串转数字，带币种/时刻/鉴权头/超时信号", async () => {
    const { fn, calls } = fakeFetch(cnyBody);
    const b = await fetchBalance(ctx(fn));
    expect(b).toEqual({ currency: "CNY", total: 3.23, at: FIXED });
    expect(calls[0]!.url).toBe(`${BASE}/user/balance`);
    expect((calls[0]!.init.headers as Record<string, string>).Authorization).toBe("Bearer sk-test");
    expect(calls[0]!.init.signal).toBeDefined(); // 必须有超时信号，否则接口卡住会拖住生成
  });
  test("多币种 → 优先取 CNY", async () => {
    const { fn } = fakeFetch({
      balance_infos: [
        { currency: "USD", total_balance: "1.00" },
        { currency: "CNY", total_balance: "7.20" },
      ],
    });
    expect((await fetchBalance(ctx(fn)))!.currency).toBe("CNY");
  });
  test("无 CNY 条目 → 取第一条", async () => {
    const { fn } = fakeFetch({ balance_infos: [{ currency: "USD", total_balance: "1.00" }] });
    expect(await fetchBalance(ctx(fn))).toEqual({ currency: "USD", total: 1, at: FIXED });
  });
  test("HTTP 非 200 → null", async () => {
    const { fn } = fakeFetch({ error: "unauthorized" }, 401);
    expect(await fetchBalance(ctx(fn))).toBeNull();
  });
  test("网络异常（fetch 抛错）→ null", async () => {
    const fn = (async () => {
      throw new Error("ECONNREFUSED");
    }) as unknown as typeof fetch;
    expect(await fetchBalance(ctx(fn))).toBeNull();
  });
  test("balance_infos 缺失或空数组 → null", async () => {
    for (const body of [{}, { balance_infos: [] }]) {
      const { fn } = fakeFetch(body);
      expect(await fetchBalance(ctx(fn))).toBeNull();
    }
  });
  test("total_balance 非数字 → null", async () => {
    const { fn } = fakeFetch({ balance_infos: [{ currency: "CNY", total_balance: "abc" }] });
    expect(await fetchBalance(ctx(fn))).toBeNull();
  });
  test("响应不是 JSON → null", async () => {
    const { fn } = fakeFetch("<html>502 Bad Gateway</html>");
    expect(await fetchBalance(ctx(fn))).toBeNull();
  });
});

describe("isLowBalance（低余额判定）", () => {
  const snap = (total: number, currency = "CNY"): BalanceSnapshot => ({ currency, total, at: FIXED });
  test("低于阈值 → true", () => {
    expect(LOW_BALANCE_THRESHOLD).toBe(1);
    expect(isLowBalance(snap(0.99))).toBe(true);
    expect(isLowBalance(snap(0))).toBe(true);
  });
  test("等于或高于阈值 → false", () => {
    expect(isLowBalance(snap(1))).toBe(false);
    expect(isLowBalance(snap(3.23))).toBe(false);
  });
  test("余额未知（null）→ false（查不到不误报）", () => {
    expect(isLowBalance(null)).toBe(false);
  });
});
