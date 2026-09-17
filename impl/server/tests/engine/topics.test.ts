import { expect, test } from "bun:test";
import {
  contentWords,
  isSimilarTopic,
  planTopic,
  TopicRegistry,
  validateTopic,
} from "../../src/engine/graph/topics";
import { FakeLLM } from "./fake-llm";

test("contentWords: 去停用词与短词，保留题材词", () => {
  expect([...contentWords("A girl finds the WRONG umbrella at a bus stop")].sort()).toEqual([
    "bus", "finds", "girl", "stop", "umbrella", "wrong",
  ]);
});

test("isSimilarTopic: 只换修饰语不算新选题（伞文事故的三个标题）", () => {
  expect(isSimilarTopic("The Yellow Umbrella", "The Blue Umbrella")).toBe(true);
  expect(isSimilarTopic("The Wrong Umbrella", "The Yellow Umbrella")).toBe(true);
});

test("isSimilarTopic: 同场景不同人物/物件判为雷同（题材没变）", () => {
  expect(
    isSimilarTopic(
      "a girl finds a lost puppy at the bus stop",
      "a boy finds a lost kitten at the bus stop",
    ),
  ).toBe(true);
});

test("isSimilarTopic: 不同题材不判重", () => {
  expect(isSimilarTopic("a boy's kite stuck in a tree", "The Old Red Bicycle")).toBe(false);
  expect(isSimilarTopic("a first piano recital", "a leaking kitchen faucet")).toBe(false);
});

test("validateTopic: 空 / 超长 / 与已用雷同", () => {
  expect(validateTopic("", [])).toBe("选题为空");
  expect(validateTopic("x".repeat(201), [])).toContain("过长");
  expect(validateTopic("The Blue Umbrella", ["The Yellow Umbrella"])).toContain("雷同");
  expect(validateTopic("a boy's kite stuck in a tree", ["The Yellow Umbrella"])).toBeUndefined();
});

test("TopicRegistry: 并发预约串行化，后到的看得到先占的选题", async () => {
  const registry = new TopicRegistry();
  const seen: string[][] = [];
  const plan = (topic: string) => async (taken: readonly string[]) => {
    seen.push([...taken]);
    await Bun.sleep(5); // 放大竞态窗口：若未串行，第二个会看到空快照
    return topic;
  };
  const [a, b] = await Promise.all([
    registry.reserve(plan("alpha story")),
    registry.reserve(plan("bravo story")),
  ]);
  expect([a, b]).toEqual(["alpha story", "bravo story"]);
  expect(seen).toEqual([[], ["alpha story"]]);
  expect([...registry.snapshot()]).toEqual(["alpha story", "bravo story"]);
});

test("TopicRegistry: 单槽失败不阻塞后续预约，空返回不登记", async () => {
  const registry = new TopicRegistry();
  const failed = await registry.reserve(async () => {
    throw new Error("规划炸了");
  }).catch((e: Error) => e.message);
  expect(failed).toBe("规划炸了");
  expect(await registry.reserve(async () => "")).toBe("");
  expect(await registry.reserve(async () => "charlie story")).toBe("charlie story");
  expect([...registry.snapshot()]).toEqual(["charlie story"]);
});

test("planTopic: 正常返回模型选题", async () => {
  const llm = new FakeLLM([null]);
  llm.topicPlans = ["a girl learns to bake bread with her aunt"];
  const topic = await planTopic({
    llm, runDate: "2026-09-17", difficulty: "LOW", category: "simple_story",
    recentTitles: [], takenTopics: [],
  });
  expect(topic).toBe("a girl learns to bake bread with her aunt");
  expect(llm.topicPrompts[0]).toContain("difficulty LOW");
  expect(llm.topicPrompts[0]).toContain("simple_story");
});

test("planTopic: 与近期标题/同批已占选题雷同 → 带拒绝反馈重问", async () => {
  const llm = new FakeLLM([null]);
  llm.topicPlans = ["The Blue Umbrella", "a boy's kite stuck in a tree"];
  const topic = await planTopic({
    llm, runDate: "2026-09-17", difficulty: "LOW", category: "simple_story",
    recentTitles: ["The Yellow Umbrella"],
    takenTopics: [],
  });
  expect(topic).toBe("a boy's kite stuck in a tree");
  expect(llm.topicPrompts).toHaveLength(2);
  // 第二轮把上一轮的被拒选题回灌给模型，并带上"已用题材"
  expect(llm.topicPrompts[1]).toContain("REJECTED");
  expect(llm.topicPrompts[1]).toContain("The Yellow Umbrella");
});

test("planTopic: 同批已占选题会传给规划器，避免批内撞题", async () => {
  const llm = new FakeLLM([null]);
  llm.topicPlans = ["The Blue Umbrella", "a fishing harbor at dawn"];
  const topic = await planTopic({
    llm, runDate: "2026-09-17", difficulty: "LOW", category: "simple_story",
    recentTitles: [], takenTopics: ["The Yellow Umbrella"],
  });
  expect(topic).toBe("a fishing harbor at dawn");
  expect(llm.topicPrompts[0]).toContain("The Yellow Umbrella");
});

test("planTopic: 两轮都规划不出不重复的选题 → undefined（退回自由选题）", async () => {
  const llm = new FakeLLM([null]);
  llm.topicPlans = ["The Blue Umbrella", "The Wrong Umbrella"];
  const topic = await planTopic({
    llm, runDate: "2026-09-17", difficulty: "LOW", category: "simple_story",
    recentTitles: ["The Yellow Umbrella"], takenTopics: [],
  });
  expect(topic).toBeUndefined();
  expect(llm.topicCalls).toBe(2);
});

test("planTopic: 规划调用抛错 → 重试一次，仍失败则 undefined（不抛给调用方）", async () => {
  const llm = new FakeLLM([null]);
  llm.topicPlans = [null, "a girl learns to bake bread with her aunt"];
  expect(
    await planTopic({
      llm, runDate: "2026-09-17", difficulty: "LOW", category: "simple_story",
      recentTitles: [], takenTopics: [],
    }),
  ).toBe("a girl learns to bake bread with her aunt");

  const alwaysFails = new FakeLLM([null]);
  alwaysFails.topicPlans = [null];
  expect(
    await planTopic({
      llm: alwaysFails, runDate: "2026-09-17", difficulty: "LOW", category: "simple_story",
      recentTitles: [], takenTopics: [],
    }),
  ).toBeUndefined();
});
