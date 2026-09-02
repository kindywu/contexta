import { expect, test } from "bun:test";
import { runPool } from "../../src/engine/utils/pool";

test("runPool: 结果按任务顺序返回（与完成先后无关）", async () => {
  const done: number[] = [];
  const results = await runPool(
    [1, 2, 3].map((n) => async () => {
      await new Promise((r) => setTimeout(r, (4 - n) * 5));
      done.push(n);
      return n * 10;
    }),
    3,
  );
  expect(done).toEqual([3, 2, 1]); // 任务 3 先完成
  expect(results).toEqual([
    { status: "fulfilled", value: 10 },
    { status: "fulfilled", value: 20 },
    { status: "fulfilled", value: 30 },
  ]);
});

test("runPool: 并发数不超过 limit", async () => {
  let active = 0;
  let maxActive = 0;
  const tasks = Array.from({ length: 10 }, () => async () => {
    active++;
    maxActive = Math.max(maxActive, active);
    await new Promise((r) => setTimeout(r, 5));
    active--;
  });
  const results = await runPool(tasks, 3);
  expect(maxActive).toBe(3);
  expect(results).toHaveLength(10);
});

test("runPool: 单个任务 reject 不影响其他任务，错误单独记录", async () => {
  const results = await runPool(
    [
      async () => "a",
      async () => {
        throw new Error("boom");
      },
      async () => "c",
    ],
    2,
  );
  expect(results).toHaveLength(3);
  expect(results[0]).toEqual({ status: "fulfilled", value: "a" });
  expect(results[1]!.status).toBe("rejected");
  if (results[1]!.status === "rejected") {
    expect((results[1]!.reason as Error).message).toBe("boom");
  }
  expect(results[2]).toEqual({ status: "fulfilled", value: "c" });
});

test("runPool: limit 为 0/负数/小数时按合法值兜底，任务照常执行", async () => {
  const tasks = [async () => 1];
  expect(await runPool(tasks, 0)).toEqual([{ status: "fulfilled", value: 1 }]);
  expect(await runPool(tasks, -3)).toEqual([{ status: "fulfilled", value: 1 }]);
  expect(await runPool(tasks, 2.5)).toEqual([{ status: "fulfilled", value: 1 }]);
});

test("runPool: 空任务列表返回空数组", async () => {
  expect(await runPool([], 5)).toEqual([]);
});
