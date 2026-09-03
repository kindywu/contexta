/**
 * 按 limit 并发执行 tasks，保序返回每个任务的 PromiseSettledResult。
 *
 * - 结果按 tasks 下标对齐，与完成先后无关；
 * - 单个任务失败只记录在对应 rejected 槽位，其余任务照常跑完；
 * - limit 钳到 ≥1 的整数：0/负数视为 1，小数向下取整；
 * - 空任务列表返回空数组。
 */
export async function runPool<T>(
  tasks: (() => Promise<T>)[],
  limit: number,
): Promise<PromiseSettledResult<T>[]> {
  const workers = Math.max(1, Math.min(Math.floor(limit), tasks.length));
  const results = new Array<PromiseSettledResult<T>>(tasks.length);
  let next = 0;
  async function worker(): Promise<void> {
    while (next < tasks.length) {
      const i = next++;
      // while 条件保证 i < tasks.length（上一行 next 边界），此处必有值
      const task = tasks[i]!;
      results[i] = await task().then(
        (value) => ({ status: "fulfilled" as const, value }),
        (reason) => ({ status: "rejected" as const, reason }),
      );
    }
  }
  await Promise.all(Array.from({ length: workers }, () => worker()));
  return results;
}
