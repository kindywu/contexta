import { performance } from "node:perf_hooks";

/** pollUntil 的轮询参数（缺省 300ms 周期 / 30s 超时）。 */
export interface PollUntilOptions {
  intervalMs?: number;
  timeoutMs?: number;
}

/**
 * 每 intervalMs 轮询 check()，直至返回 true 或超时。
 *
 * - 轮询期间 check() 抛错（如页面导航过渡期 evaluate 拒绝）会被吞掉，
 *   继续下一个周期；
 * - 超时静默返回 false（不抛错），由调用方决定如何处理
 *   （继承原 waitUntil 的"按当前状态继续"语义）。
 */
export async function pollUntil(
  check: () => Promise<boolean>,
  options: PollUntilOptions = {},
): Promise<boolean> {
  const intervalMs = options.intervalMs ?? 300;
  const timeoutMs = options.timeoutMs ?? 30_000;
  const t0 = performance.now();
  while (performance.now() - t0 < timeoutMs) {
    try {
      if (await check()) return true;
    } catch {
      // 过渡期异常，继续等下个周期
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  return false;
}
