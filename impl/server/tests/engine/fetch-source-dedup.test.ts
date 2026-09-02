import { expect, test } from "bun:test";
import { chooseArticleNode, fetchLinksNode, type NodeDeps } from "../../src/engine/graph/nodes";
import type { LLM } from "../../src/engine/llm";
import type { SiteFetcher, SiteEntry } from "../../src/engine/sites";

const llm = {} as LLM;

function makeDeps(usedUrls: Set<string>, links: { title: string; url: string }[]): NodeDeps {
  const adapter = {
    name: "chinadaily",
    fetchLinks: async () => links as never,
    fetchArticle: async (l: { title: string; url: string }) => ({
      title: l.title,
      url: l.url,
      html: `<p>${"正文一字一字".repeat(20)}</p>`, // >100 字符（6字 × 20 + <p></p> = 127）
    }),
  } satisfies SiteFetcher as never;
  const entry = {
    name: "chinadaily",
    url: "https://www.chinadaily.com.cn",
    categories: ["news"],
    adapter,
  } satisfies SiteEntry as never;
  return { llm, sitesByCategory: { news: [entry] }, rng: () => 0, usedUrls } as NodeDeps;
}

test("fetchLinks/chooseArticle: 近期用过的 URL 被过滤，选中的加入共享 Set", async () => {
  const used = new Set<string>();
  const links = [
    { title: "old", url: "https://cdn.example.com/a?id=1" }, // 与 recentUsedUrls 归一化后相同（stripQuery）
    { title: "new", url: "https://cdn.example.com/b" },
  ];
  const deps = makeDeps(used, links);
  const list = await fetchLinksNode(
    { category: "news", recentUsedUrls: ["https://cdn.example.com/a"] } as never,
    deps,
  );
  const picked = await chooseArticleNode(
    { category: "news", sourceLinks: list.sourceLinks, sourceSiteName: list.sourceSiteName } as never,
    deps,
  );
  expect(picked.sourceUrl).toBe("https://cdn.example.com/b");
  expect(used.has("https://cdn.example.com/b")).toBe(true);
});

test("fetchLinks: 全部站点列表与近期重复 → 抛错（不静默重复）", async () => {
  const deps = makeDeps(new Set(), [
    { title: "old1", url: "https://cdn.example.com/a" },
    { title: "old2", url: "https://cdn.example.com/b" },
  ]);
  await expect(
    fetchLinksNode(
      { category: "news", recentUsedUrls: ["https://cdn.example.com/a", "https://cdn.example.com/b"] } as never,
      deps,
    ),
  ).rejects.toThrow(/所有权威站点列表抓取失败/);
});

test("chooseArticle: state 缺 recentUsedUrls（旧 checkpoint）→ 按 [] 处理不炸", async () => {
  const used = new Set<string>();
  const deps = makeDeps(used, [{ title: "only", url: "https://cdn.example.com/a" }]);
  const list = await fetchLinksNode({ category: "news" } as never, deps);
  const picked = await chooseArticleNode(
    { category: "news", sourceLinks: list.sourceLinks, sourceSiteName: list.sourceSiteName } as never,
    deps,
  );
  expect(picked.sourceUrl).toBe("https://cdn.example.com/a");
});

test("chooseArticle: 正文过短 → 换下一篇（不重复选中），列表耗尽 → 抛错", async () => {
  const llmLocal = {} as LLM;
  const adapter = {
    name: "chinadaily",
    fetchLinks: async () => [],
    fetchArticle: async (l: { title: string; url: string }) => ({
      title: l.title,
      url: l.url,
      html: l.url.includes("short") ? "太短" : `<p>${"正文长文".repeat(30)}</p>`, // 4字×30+<p></p>=127 > 100
    }),
  } satisfies SiteFetcher as never;
  const entry = {
    name: "chinadaily",
    url: "https://www.chinadaily.com.cn",
    categories: ["news"],
    adapter,
  } satisfies SiteEntry as never;
  const deps = { llm: llmLocal, sitesByCategory: { news: [entry] }, rng: () => 0, usedUrls: new Set<string>() } as NodeDeps;
  // 列表耗尽（唯一一篇过短）→ 抛错
  await expect(
    chooseArticleNode(
      { category: "news", sourceSiteName: "chinadaily", sourceLinks: [{ title: "short", url: "https://cdn.example.com/short" }] } as never,
      deps,
    ),
  ).rejects.toThrow(/列表耗尽/);
  // 短篇在前 → 换到下一篇拿到好稿
  const picked = await chooseArticleNode(
    {
      category: "news", sourceSiteName: "chinadaily",
      sourceLinks: [
        { title: "short", url: "https://cdn.example.com/short" },
        { title: "good", url: "https://cdn.example.com/good" },
      ],
    } as never,
    deps,
  );
  expect(picked.sourceUrl).toBe("https://cdn.example.com/good");
});

