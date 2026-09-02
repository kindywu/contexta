import { expect, test } from "bun:test";
import type { LLM } from "../../src/engine/llm";
import { route, type NodeDeps } from "../../src/engine/graph/nodes";
import type { SiteFetcher, SiteEntry, SiteName } from "../../src/engine/sites";
import type { Category } from "../../src/engine/schema";

const llm = {} as LLM;

/** route() 只读各列表长度；条目桩最小化保持模型诚实。 */
function stubEntry(name: SiteName): SiteEntry {
  return { name, url: "https://example.com", categories: [], adapter: {} as SiteFetcher };
}

function deps(byCategory: Partial<Record<Category, SiteEntry[]>>): NodeDeps {
  return { llm, sitesByCategory: byCategory, rng: Math.random };
}

test("route: 类别配置了来源站点 → A", () => {
  expect(
    route({ category: "news" } as never, deps({ news: [stubEntry("chinadaily")] })),
  ).toBe("A");
});

test("route: 类别未配置站点 → B（即使类别是 news/expository）", () => {
  expect(route({ category: "news" } as never, deps({}))).toBe("B");
  expect(route({ category: "expository" } as never, deps({}))).toBe("B");
});

test("route: 只配置了其他类别不影响本类别 → B", () => {
  expect(
    route({ category: "simple_story" } as never, deps({ news: [stubEntry("chinadaily")] })),
  ).toBe("B");
});
