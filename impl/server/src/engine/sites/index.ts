/**
 * 站点适配器注册表与配置入口。
 * 外界通过 siteAdapters 引用各站点实现；站点配置（sites.config.ts）经
 * defineSites 校验、deriveByCategory 派生类别 → 条目映射。
 */

import { chinadaily } from "./chinadaily";
import { tencent } from "./tencent";
import type { Category } from "../schema";
import type { SiteFetcher } from "./common";

export type { ArticleHtml, ArticleLink, AnchorSnap, SiteFetcher } from "./common";
export { pickRandom, cleanArticleScript, fetchAnchorSnapshots, fetchArticleHTML } from "./common";

/**
 * 适配器注册表：哪些站点有实现，唯一权威。
 */
export const siteAdapters = {
  chinadaily,
  tencent,
} as const satisfies Record<string, SiteFetcher>;

/** 站点名 = 注册表键（枚举从注册表派生，不再手写）。 */
export type SiteName = keyof typeof siteAdapters;

/** 站点配置条目（sites.config.ts 里声明；name 与 adapter.name 必须一致）。 */
export interface SiteEntry {
  name: SiteName;
  /** 运行时抓取入口（首页 URL），由配置提供 */
  url: string;
  categories: Category[];
  adapter: SiteFetcher;
}

/** 条目校验：name 与实现自带名称不一致 → 模块加载即抛错（fail-fast）。 */
export function defineSites(entries: SiteEntry[]): SiteEntry[] {
  for (const e of entries) {
    if (e.adapter.name !== e.name) {
      throw new Error(
        `sites.config.ts 中站点 ${e.name} 与适配器 ${e.adapter.name} 不一致`,
      );
    }
  }
  return entries;
}

/** sites → 类别 → 条目列表（按配置文件顺序；未配置类别无该键）。 */
export function deriveByCategory(
  entries: SiteEntry[],
): Partial<Record<Category, SiteEntry[]>> {
  const byCategory: Partial<Record<Category, SiteEntry[]>> = {};
  for (const e of entries) {
    for (const c of e.categories) {
      (byCategory[c] ??= []).push(e);
    }
  }
  return byCategory;
}
