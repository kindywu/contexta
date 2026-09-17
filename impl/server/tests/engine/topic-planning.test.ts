import { expect, test } from "bun:test";
import { buildArticleGraph } from "../../src/engine/graph/graph";
import { pickTopicNode } from "../../src/engine/graph/nodes";
import { TopicRegistry } from "../../src/engine/graph/topics";
import { FakeLLM } from "./fake-llm";

/**
 * 图级回归（2026-09-17 三篇伞文事故）：pathB 槽位在生成前先定选题，
 * 同批并发槽位共享登记簿 → 选题互不重复且写进生成 prompt。
 * sitesByCategory 传空 → 所有类别都判 pathB（不走站点抓取）。
 */
function buildPathBGraph(llm: FakeLLM, topicRegistry?: TopicRegistry) {
  return buildArticleGraph({
    deps: { llm, sitesByCategory: {}, rng: () => 0.1, topicRegistry },
  });
}

test("pickTopic: pathB 生成 prompt 带选题；同批并发槽位选题互不重复", async () => {
  const fake = new FakeLLM([null]);
  const registry = new TopicRegistry();
  const graph = buildPathBGraph(fake, registry);
  // 并发两个槽位（同批），共享登记簿
  const [a, b] = await Promise.all([
    graph.invoke({ runDate: "2026-09-17", difficulty: "LOW", recentTitles: [], recentUsedUrls: [] }),
    graph.invoke({ runDate: "2026-09-17", difficulty: "LOW", recentTitles: [], recentUsedUrls: [] }),
  ]);
  expect(a.outcome).toBe("success");
  expect(b.outcome).toBe("success");

  expect(fake.generatePrompts).toHaveLength(2);
  const topics = [a.topic, b.topic] as string[];
  expect(topics[0]).toBeTruthy();
  expect(topics[0]).not.toBe(topics[1]);
  // 规划器第二轮看得到第一轮已占的选题（串行取号的证据）
  expect(fake.topicPrompts[1]).toContain(topics[0]!);
  // 选题落进生成 prompt（带"不要换题"约束），不再是"自己挑一个"
  for (const prompt of fake.generatePrompts) {
    expect(prompt).toContain("TOPIC — write about exactly this subject");
  }
  expect(fake.generatePrompts[0]).toContain(topics[0]!);
  expect(fake.generatePrompts[1]).toContain(topics[1]!);
  expect(fake.generatePrompts[0]).not.toContain('choose a topic and angle NOT similar');
});

test("pickTopic: 规划失败/未注入登记簿 → 退回自由选题，生成照常完成", async () => {
  // 未注入登记簿
  const noRegistry = new FakeLLM([null]);
  const out1 = await buildPathBGraph(noRegistry).invoke({
    runDate: "2026-09-17", difficulty: "LOW", recentTitles: ["The Old Red Bicycle"], recentUsedUrls: [],
  });
  expect(out1.outcome).toBe("success");
  expect(out1.topic ?? "").toBe("");
  expect(noRegistry.topicCalls).toBe(0);
  expect(noRegistry.generatePrompts[0]).toContain("choose a topic and angle NOT similar");

  // 规划调用连续抛错 → 兜底不写 topic，生成不中断
  const failing = new FakeLLM([null]);
  failing.topicPlans = [null, null];
  const out2 = await buildPathBGraph(failing, new TopicRegistry()).invoke({
    runDate: "2026-09-17", difficulty: "LOW", recentTitles: [], recentUsedUrls: [],
  });
  expect(out2.outcome).toBe("success");
  expect(out2.topic ?? "").toBe("");
  expect(failing.generatePrompts).toHaveLength(1);
});

test("pickTopic: 状态里已有选题（断点恢复）→ 不重复规划", async () => {
  const fake = new FakeLLM([null]);
  const update = await pickTopicNode(
    { runDate: "2026-09-17", difficulty: "LOW", category: "simple_story", topic: "a boy's kite stuck in a tree" } as never,
    { llm: fake, sitesByCategory: {}, rng: () => 0, topicRegistry: new TopicRegistry() },
  );
  expect(update).toEqual({});
  expect(fake.topicCalls).toBe(0);
});

test("pickTopic: 校验未通过（与近期标题雷同）→ 重问仍撞 → 不写 topic", async () => {
  const fake = new FakeLLM([null]);
  fake.topicPlans = ["The Blue Umbrella", "The Wrong Umbrella"];
  const out = await buildPathBGraph(fake, new TopicRegistry()).invoke({
    runDate: "2026-09-17",
    difficulty: "LOW",
    recentTitles: ["The Yellow Umbrella"],
    recentUsedUrls: [],
  });
  expect(out.outcome).toBe("success");
  expect(out.topic ?? "").toBe("");
  expect(fake.topicCalls).toBe(2);
});
