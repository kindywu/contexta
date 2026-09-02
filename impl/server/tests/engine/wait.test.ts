import { expect, test } from "bun:test";
import { pollUntil } from "../../src/engine/utils/wait";

test("pollUntil: 条件满足立即返回 true", async () => {
  const ok = await pollUntil(async () => true, { intervalMs: 1, timeoutMs: 100 });
  expect(ok).toBe(true);
});

test("pollUntil: 检查抛错时继续轮询，直至成功", async () => {
  let calls = 0;
  const ok = await pollUntil(
    async () => {
      calls++;
      if (calls < 3) throw new Error("过渡期");
      return true;
    },
    { intervalMs: 1, timeoutMs: 100 },
  );
  expect(ok).toBe(true);
  expect(calls).toBe(3);
});

test("pollUntil: 超时后静默返回 false（不抛错）", async () => {
  const ok = await pollUntil(async () => false, { intervalMs: 5, timeoutMs: 50 });
  expect(ok).toBe(false);
});
