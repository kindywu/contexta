import { expect, test } from "bun:test";
import { buildArticleGraph } from "../../src/engine/graph/graph";
import { computeFreshLinks } from "../../src/engine/graph/nodes";
import type { SiteEntry } from "../../src/engine/sites";
import type { ArticleLink } from "../../src/engine/sites";
import { FakeLLM, type FactCard } from "./fake-llm";

const FULL_CARD: FactCard = {
  who: "Zhang", what: "announces the policy", when: "2026-08-30", where: "Beijing",
  why: "", how: "", keyNumbers: ["3"], keyNames: ["Zhang"],
};

/** 假站点：固定列表，fetchArticle 记录被选中的 URL。 */
function fakeSite(links: ArticleLink[]): { entry: SiteEntry; fetched: string[] } {
  const fetched: string[] = [];
  const entry: SiteEntry = {
    name: "chinadaily", // 类型限定为注册表内站点名；行为由下方假 adapter 全决定
    url: "https://fakesite.dev",
    categories: ["news"],
    adapter: {
      name: "chinadaily",
      fetchLinks: async () => links,
      fetchArticle: async (l) => {
        fetched.push(l.url);
        return {
          title: l.title,
          url: l.url,
          // 重复 4 段确保 ≥100 字符（低于阈值会被当作"正文过短"滤掉）
          html: `<p>${l.title} 正文示例内容，用于测试换源重试；这段描述足够长以超过一百字符阈值限制。</p>`.repeat(4),
        };
      },
    },
  };
  return { entry, fetched };
}

const LINKS: ArticleLink[] = [
  { title: "A1", url: "https://fakesite.dev/a/1" },
  { title: "A2", url: "https://fakesite.dev/a/2" },
  { title: "A3", url: "https://fakesite.dev/a/3" },
];

/** 用假站点 + 假 LLM 构造路径 A 图（rng 固定选 category=news，避免命中真实站点）。 */
function buildPathAGraph(llm: FakeLLM, entry: SiteEntry, usedUrls?: Set<string>) {
  return buildArticleGraph({
    deps: {
      llm,
      sitesByCategory: { news: [entry] },
      rng: () => 0.1, // MEDIUM 列表 index 0 = news；换源取列表首位（已选者移出）
      usedUrls,
    },
  });
}

test("computeFreshLinks: 原始 URL 去重 + stripQuery 过滤近 5 天/本轮已用", () => {
  const links: ArticleLink[] = [
    { title: "A", url: "https://x.com/a" },
    { title: "A exact dup", url: "https://x.com/a" }, // 原始 URL 重复 → 只留首次
    { title: "A query-var", url: "https://x.com/a?q=1" },
    { title: "B", url: "https://x.com/b" },
    { title: "C", url: "https://x.com/c" },
  ];
  const fresh = computeFreshLinks(links, ["https://x.com/b"], new Set(["https://x.com/c"]));
  expect(fresh.map((l) => l.url)).toEqual(["https://x.com/a", "https://x.com/a?q=1"]);
});

test("extractFacts 空卡换源重试：前 2 次空、第 3 次成功 → success 且 3 篇来源不同", async () => {
  const { entry, fetched } = fakeSite(LINKS);
  const fake = new FakeLLM([null], [null, null, FULL_CARD]);
  const graph = buildPathAGraph(fake, entry);
  const out = await graph.invoke({
    runDate: "2026-08-30",
    difficulty: "MEDIUM",
    recentTitles: [],
    recentUsedUrls: [],
  });
  expect(out.outcome).toBe("success");
  expect(new Set(fetched).size).toBe(3); // 换源不重复：三抽三篇不同
  expect(fake.factCalls).toBe(3);
  expect(fake.generatePrompts).toHaveLength(1); // 抽取成功后才进入生成
});

test("extractFacts 连续 3 次空卡 → rejected（不再进入生成）", async () => {
  const { entry, fetched } = fakeSite(LINKS);
  const fake = new FakeLLM([null], [null, null, null]);
  const graph = buildPathAGraph(fake, entry);
  const out = await graph.invoke({
    runDate: "2026-08-30",
    difficulty: "MEDIUM",
    recentTitles: [],
    recentUsedUrls: [],
  });
  expect(out.outcome).toBe("rejected");
  expect(out.reason).toContain("缺少可靠依据");
  expect(fetched).toHaveLength(3);
  expect(fake.generatePrompts).toHaveLength(0);
});

test("extractFacts 一次成功 → 单轮完成", async () => {
  const { entry, fetched } = fakeSite(LINKS);
  const fake = new FakeLLM([null], [FULL_CARD]);
  const graph = buildPathAGraph(fake, entry);
  const out = await graph.invoke({
    runDate: "2026-08-30",
    difficulty: "MEDIUM",
    recentTitles: [],
    recentUsedUrls: [],
  });
  expect(out.outcome).toBe("success");
  expect(fetched).toHaveLength(1);
  expect(fake.factCalls).toBe(1);
});
