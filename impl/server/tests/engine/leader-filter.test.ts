import { expect, test } from "bun:test";
import { buildArticleGraph } from "../../src/engine/graph/graph";
import {
  chooseArticleNode,
  fetchLinksNode,
  LEADERS_SOURCE_REJECTION_MESSAGE,
  mentionsCoreLeader,
  type NodeDeps,
} from "../../src/engine/graph/nodes";
import type { LLM } from "../../src/engine/llm";
import type { SiteEntry } from "../../src/engine/sites";
import type { ArticleLink } from "../../src/engine/sites";
import { FakeLLM, type FactCard } from "./fake-llm";

const llm = {} as LLM;

function depsFor(entry: SiteEntry, usedUrls = new Set<string>()): NodeDeps {
  return { llm, sitesByCategory: { news: [entry] }, rng: () => 0.1, usedUrls } as NodeDeps;
}

function siteFor(links: ArticleLink[], htmlFor: (l: ArticleLink) => string, fetched: string[] = []): SiteEntry {
  return {
    name: "chinadaily",
    url: "https://fakesite.dev",
    categories: ["news"],
    adapter: {
      name: "chinadaily",
      fetchLinks: async () => links,
      fetchArticle: async (l: ArticleLink) => {
        fetched.push(l.url);
        return { title: l.title, url: l.url, html: htmlFor(l) };
      },
    },
  } as never;
}

const GOOD = (t: ArticleLink | string) => `<p>${String(t)} ${"正文内容".repeat(40)}</p>`; // >100 字符

test("mentionsCoreLeader: 名单内姓名命中, 其余不命中", () => {
  expect(mentionsCoreLeader("习近平强调要保护环境")).toBe(true);
  expect(mentionsCoreLeader("猫和熊猫都很可爱")).toBe(false);
});

test("fetchLinks: 标题含受限人名的候选被过滤(不选篇)", async () => {
  const fetched: string[] = [];
  const entry = siteFor(
    [
      { title: "习近平在大会上致辞", url: "https://fakesite.dev/leader" },
      { title: "猫和熊猫的故事", url: "https://fakesite.dev/fluffy" },
    ],
    GOOD,
    fetched,
  );
  const list = (await fetchLinksNode({ category: "news", recentUsedUrls: [] } as never, depsFor(entry))) as never as {
    sourceLinks: ArticleLink[];
  };
  expect(list.sourceLinks.map((l) => l.url)).toEqual(["https://fakesite.dev/fluffy"]);
  await chooseArticleNode(
    { category: "news", sourceLinks: list.sourceLinks, sourceSiteName: "chinadaily" } as never,
    depsFor(entry),
  );
  expect(fetched).toEqual(["https://fakesite.dev/fluffy"]); // 名单候选连正文都不抓
});

test("chooseArticle: 标题不带人名但正文含名单 → 跳过换下一篇", async () => {
  const entry = siteFor(
    [
      { title: "毫无波澜的标题", url: "https://fakesite.dev/a" }, // 正文含名单
      { title: "干净的标题", url: "https://fakesite.dev/b" },
    ],
    (l) => (l.url.endsWith("/a") ? `<p>${"邓小平与改革开放".repeat(20)}</p>` : GOOD("clean")),
  );
  const picked = await chooseArticleNode(
    { category: "news", sourceSiteName: "chinadaily", sourceLinks: [{ title: "毫无波澜的标题", url: "https://fakesite.dev/a" }, { title: "干净的标题", url: "https://fakesite.dev/b" }] } as never,
    depsFor(entry),
  );
  expect(picked.sourceUrl).toBe("https://fakesite.dev/b");
});

test("chooseArticle: 候选全部正文含名单 → rejected(不再抛 error)", async () => {
  const entry = siteFor(
    [{ title: "t1", url: "https://fakesite.dev/a" }],
    () => `<p>${"李克强与生活".repeat(20)}</p>`,
  );
  const out = (await chooseArticleNode(
    { category: "news", sourceSiteName: "chinadaily", sourceLinks: [{ title: "t1", url: "https://fakesite.dev/a" }] } as never,
    depsFor(entry),
  )) as { outcome: string; reason: string };
  expect(out.outcome).toBe("rejected");
  expect(out.reason).toContain("受限");
});

test("fetchLinks: 站点列表全部标题含名单且无他站可换 → rejected(业务终态,非 error)", async () => {
  const entry = siteFor(
    [{ title: "习近平在大会上致辞", url: "https://fakesite.dev/leader" }],
    GOOD,
  );
  const out = (await fetchLinksNode({ category: "news", recentUsedUrls: [] } as never, depsFor(entry))) as {
    outcome: string;
    reason: string;
  };
  expect(out.outcome).toBe("rejected");
  expect(out.reason).toBe(LEADERS_SOURCE_REJECTION_MESSAGE);
});

test("图内(path A): 候选全部含名单 → 最终 rejected, 不进入生成/判官", async () => {
  const entry = siteFor(
    [
      { title: "丁薛祥调研纪实", url: "https://fakesite.dev/x/1" },
      { title: "蔡奇考察现场", url: "https://fakesite.dev/x/2" },
      { title: "李希出席仪式", url: "https://fakesite.dev/x/3" },
    ],
    GOOD,
  );
  const fake = new FakeLLM([null], [null] as (FactCard | null)[]);
  const graph = buildArticleGraph({
    deps: { llm: fake, sitesByCategory: { news: [entry] }, rng: () => 0.1, usedUrls: new Set() },
  });
  const out = await graph.invoke({
    runDate: "2026-08-30",
    difficulty: "MEDIUM",
    recentTitles: [],
    recentUsedUrls: [],
  });
  expect(out.outcome).toBe("rejected");
  expect(out.reason).toContain("受限");
  expect(fake.generatePrompts).toHaveLength(0);
  expect(fake.validateCalls).toBe(0);
});
