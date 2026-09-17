import { expect, test } from "bun:test";
import {
  buildGenerateUserContent,
  buildTopicPlannerUser,
} from "../../src/engine/graph/prompts";

const base = {
  category: "news" as const,
  path: "B" as const,
  sourceTitle: "",
  sourceUrl: "",
  sourceMarkdown: "",
  factSheetJson: "{}",
  lastViolations: [],
  recentTitles: ["China's summer travel boom", "Tea culture"],
};

test("buildGenerateUserContent: 空 recentTitles 不输出雷同块", () => {
  const user = buildGenerateUserContent({ ...base, recentTitles: [] });
  expect(user).not.toContain("RECENTLY PUBLISHED ARTICLES");
});

test("buildGenerateUserContent: 有近期标题时输出块", () => {
  const user = buildGenerateUserContent(base);
  expect(user).toContain("RECENTLY PUBLISHED ARTICLES");
  expect(user).toContain('"China\'s summer travel boom"');
  expect(user).toContain('"Tea culture"');
});

test("buildGenerateUserContent: 带选题时输出 TOPIC 行，且去重块改为'题材已定'口径", () => {
  const user = buildGenerateUserContent({ ...base, topic: "a fishing harbor at dawn" });
  expect(user).toContain("TOPIC — write about exactly this subject");
  expect(user).toContain("a fishing harbor at dawn");
  // 选题与"自己挑一个不一样的"是互相打架的两条指令：带选题时必须换措辞
  expect(user).not.toContain("choose a topic and angle NOT similar");
  expect(user).toContain("ALREADY PUBLISHED RECENTLY");
  expect(user).toContain('"Tea culture"');
});

test("buildGenerateUserContent: 空选题/纯空白 → 不输出 TOPIC 行（退回自由选题）", () => {
  for (const topic of ["", "   "]) {
    const user = buildGenerateUserContent({ ...base, topic });
    expect(user).not.toContain("TOPIC —");
    expect(user).toContain("RECENTLY PUBLISHED ARTICLES");
  }
});

test("buildTopicPlannerUser: 槽位规格 + 已用标题/已占选题都带给规划器", () => {
  const user = buildTopicPlannerUser({
    runDate: "2026-09-17",
    difficulty: "LOW",
    category: "simple_story",
    recentTitles: ["The Yellow Umbrella"],
    takenTopics: ["a boy's kite stuck in a tree"],
  });
  expect(user).toContain("LOW");
  expect(user).toContain("simple_story");
  expect(user).toContain("A2"); // 难度按 CEFR 标注
  expect(user).toContain("The Yellow Umbrella");
  expect(user).toContain("a boy's kite stuck in a tree");
});
