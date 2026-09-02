import { expect, test } from "bun:test";
import { buildGenerateUserContent } from "../../src/engine/graph/prompts";

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
