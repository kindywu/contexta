import { expect, test } from "bun:test";
import {
  defineSites,
  deriveByCategory,
  siteAdapters,
  type SiteEntry,
} from "../../src/engine/sites";

const entries: SiteEntry[] = [
  { name: "chinadaily", url: "https://www.chinadaily.com.cn", categories: ["news", "expository"], adapter: siteAdapters.chinadaily },
  { name: "tencent", url: "https://news.qq.com", categories: ["news"], adapter: siteAdapters.tencent },
];

test("siteAdapters: 注册表包含且仅包含 chinadaily/tencent", () => {
  expect(Object.keys(siteAdapters).sort()).toEqual(["chinadaily", "tencent"]);
});

test("defineSites: 合法条目原样返回", () => {
  expect(defineSites(entries)).toBe(entries);
});

test("defineSites: name 与 adapter.name 不一致抛错", () => {
  expect(() =>
    defineSites([
      { name: "chinadaily", url: "https://news.qq.com", categories: ["news"], adapter: siteAdapters.tencent },
    ]),
  ).toThrow(/不一致/);
});

test("deriveByCategory: 按类别分组且保持配置文件顺序", () => {
  const byCategory = deriveByCategory(entries);
  expect(byCategory.news).toEqual(entries);
  expect(byCategory.expository).toEqual([entries[0]!]);
  expect(byCategory.simple_story).toBeUndefined();
});

test("sites.config: 配置内容为 chinadaily/tencent 且 byCategory 派生正确", async () => {
  const { sites, byCategory } = await import("../../src/engine/sites.config");
  expect(sites.map((s) => s.name).sort()).toEqual(["chinadaily", "tencent"]);
  expect(byCategory.news?.map((s) => s.name)).toEqual(["chinadaily", "tencent"]);
  expect(byCategory.expository?.map((s) => s.name)).toEqual(["chinadaily", "tencent"]);
});
