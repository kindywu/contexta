import { expect, test } from "bun:test";
import { buildArticleGraph } from "../../src/engine/graph/graph";
import { collectArticleText, coreLeadersNode } from "../../src/engine/graph/nodes";
import { buildGenerateSystemPrompt } from "../../src/engine/graph/prompts";
import { memberList } from "../../src/engine/const/coreLeaders";
import { FakeLLM } from "./fake-llm";

function draft(titleZh: string, paragraphsZh: string[]) {
  return {
    titleEn: "A Clean English Title",
    titleZh,
    paragraphs: paragraphsZh.map((zh, i) => ({ en: `EN ${i}`, zh })),
  };
}

test("coreLeadersNode: 中文正文/标题出现受限人名 → 立即 rejected（无 LLM 检查）", async () => {
  const _deps = { llm: FakeLLM.prototype as never, sitesByCategory: {}, rng: () => 0 };
  const hitBody = await coreLeadersNode(
    { draft: draft("普通标题", ["熊猫是中国的国宝。", "这篇文章提到邓小平的贡献。"]) } as never,
    _deps,
  );
  expect(hitBody.outcome).toBe("rejected");
  expect(hitBody.reason).toContain("受限人物");

  const hitTitle = await coreLeadersNode(
    { draft: draft("习近平的故事", ["正文只谈熊猫。"]) } as never,
    _deps,
  );
  expect(hitTitle.outcome).toBe("rejected");
});

test("coreLeadersNode: 无命中 → 原样通过（不写 outcome）", async () => {
  const _deps = { llm: FakeLLM.prototype as never, sitesByCategory: {}, rng: () => 0 };
  const out = await coreLeadersNode(
    { draft: draft("熊猫的春天", ["熊猫是中国的国宝。", "多喝水对身体好。"]) } as never,
    _deps,
  );
  expect(out).toEqual({});
});

test("coreLeadersNode: 英文正文只出现拼音（如 Mao Zedong）不命中——名单为中文名", async () => {
  const _deps = { llm: FakeLLM.prototype as never, sitesByCategory: {}, rng: () => 0 };
  const out = await coreLeadersNode(
    {
      draft: {
        titleEn: "A Clean English Title",
        titleZh: "熊猫的春天",
        paragraphs: [{ en: "Mao Zedong was mentioned in this English text.", zh: "正文。" }],
      },
    } as never,
    _deps,
  );
  expect(out).toEqual({});
});

test("collectArticleText: 汇总标题与段落中英文（供名单匹配）", () => {
  const text = collectArticleText(draft("中文标题", ["中段1"]));
  expect(text).toContain("A Clean English Title");
  expect(text).toContain("中文标题");
  expect(text).toContain("中段1");
});

test("生成 prompt: pathB 增加名单禁止块, pathA 不带", () => {
  const pB = buildGenerateSystemPrompt({ difficulty: "HIGH", category: "debate_speech", path: "B" });
  expect(pB).toContain("ABSOLUTELY FORBIDDEN");
  expect(pB).toContain(memberList[0]!); // 毛泽东
  expect(pB).toContain(memberList[memberList.length - 1]!); // 徐才厚
  const pA = buildGenerateSystemPrompt({ difficulty: "HIGH", category: "news", path: "A" });
  expect(pA).not.toContain("ABSOLUTELY FORBIDDEN");
});

test("图内: pathB 生成稿标题含受限人名 → rejected, 判官不会被调用", async () => {
  const fake = new FakeLLM([null], null, "A Clean English Title", "毛泽东青年时代的故事");
  const graph = buildArticleGraph({
    deps: { llm: fake, sitesByCategory: {}, rng: () => 0.1 },
  });
  const out = await graph.invoke({
    runDate: "2026-08-30",
    difficulty: "MEDIUM",
    recentTitles: [],
    recentUsedUrls: [],
  });
  expect(out.outcome).toBe("rejected");
  expect(out.reason).toContain("受限人物");
  expect(fake.generatePrompts).toHaveLength(1);
  expect(fake.validateCalls).toBe(0); // 名单检查先于判官,已拦截
});
