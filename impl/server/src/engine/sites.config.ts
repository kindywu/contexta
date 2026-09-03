/**
 * 权威来源站点配置（声明式，替换 sites.yaml）。
 * 规则：
 * - name 必须是 src/sites/index.ts siteAdapters 注册表中的键；
 * - url 为运行时抓取入口（适配器 fetchLinks 的参数），错误域名会在抓取期暴露（列表为空）；
 * - categories 必须是 src/schema.ts 中 11 个合法值之一（类型约束）；
 * - 某类别配置 ≥1 个站点 → 生成流程走 path A（抓取权威来源支撑）；
 *   未配置任何站点的类别 → 走 path B（模型知识生成）。
 * 加新站点：写适配器 + 在下方数组加一行。
 */
import { defineSites, deriveByCategory, siteAdapters } from "./sites";

export const sites = defineSites([
  {
    name: "chinadaily",
    url: "https://www.chinadaily.com.cn",
    categories: ["news", "expository"],
    adapter: siteAdapters.chinadaily,
  },
  {
    name: "tencent",
    url: "https://news.qq.com",
    categories: ["news", "expository"],
    adapter: siteAdapters.tencent,
  },
]);

/** 类别 → 该类别可用站点条目（按配置文件顺序）。 */
export const byCategory = deriveByCategory(sites);
