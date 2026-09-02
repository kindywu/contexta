/**
 * 站点抓取的公共部分：浏览器视图（Bun.WebView）、锚点快照采集、
 * 正文 HTML 提取与清洗、列表清洗小工具。
 * 具体站点的抽取规则见 chinadaily.ts / tencent.ts。
 */

import { performance } from "node:perf_hooks";
import { fmtMs } from "../utils/format";
import { pollUntil } from "../utils/wait";

export interface ArticleLink {
  title: string;
  url: string;
}

/** 文章正文抓取结果：标题 + 原文 URL + 清洗后的正文 HTML。 */
export interface ArticleHtml {
  title: string;
  url: string;
  html: string;
}

/**
 * 站点访问的统一接口：第一批（列表）+ 第二批（正文）。
 * 每个站点一份实现（见 chinadaily.ts / tencent.ts），外界不感知具体解析差异。
 */
export interface SiteFetcher {
  readonly name: string; // 适配器自带名称；配置条目 name 必须与之一致（defineSites 守卫）
  /** 首页文章列表（标题 + URL）；homeUrl 由站点配置（sites.config.ts）传入 */
  fetchLinks(homeUrl: string): Promise<ArticleLink[]>;
  /** 抓取指定文章的正文 HTML（已去除其他链接和广告）。 */
  fetchArticle(link: ArticleLink): Promise<ArticleHtml>;
}

/** 浏览器内取到的锚点快照：文本、href、class 及直接子元素文本。 */
export interface AnchorSnap {
  href: string;
  text: string;
  cls: string;
  childTexts: string[];
}

/** 在页面里执行选择器取快照的脚本（evaluate 只收表达式，包成 IIFE）。 */
const snapshotScript = (selector: string) => `(() => {
  const anchors = [...document.querySelectorAll(${JSON.stringify(selector)})];
  return anchors.map((a) => ({
    href: a.href,
    text: (a.textContent ?? "").replace(/\\s+/g, " ").trim(),
    cls: a.className,
    childTexts: [...a.children].map((c) =>
      (c.textContent ?? "").replace(/\\s+/g, " ").trim(),
    ),
  }));
})()`;

/**
 * 软导航：给页面赋值 location.href，立即返回，不等页面完整加载。
 * Bun.WebView.navigate() 会等全部子资源（图片、广告、统计脚本）加载完才 resolve，
 * 慢站点（实测中国日报首页挂起 130s+）因此极为耗时；而 DOM 实际 1~2s 就绪，
 * 所以我们改为自行跳转 + 轮询 DOM。
 */
async function navigateLite(view: Bun.WebView, pageUrl: string): Promise<void> {
  if (!view.url) await view.navigate("about:blank"); // 首次使用先建立稳定的空白上下文
  await view.evaluate(`location.href = ${JSON.stringify(pageUrl)}`);
}

/**
 * 打开页面，等动态新闻列表填充后，返回匹配选择器的锚点快照。
 * 页面加载完成后视图即关闭，快照数组与浏览器生命周期无关。
 */
export async function fetchAnchorSnapshots(
  pageUrl: string,
  selector: string,
): Promise<AnchorSnap[]> {
  const view = new Bun.WebView({ width: 1440, height: 2000 });
  try {
    await navigateLite(view, pageUrl);
    const tWait = performance.now();
    // 列表是 JS 懒加载的（实测腾讯 6s 左右注入），必须等选择器真正命中——
    // 不能用"页面里 a 数量多"之类的替代条件，页脚链接会提前满足导致空列表。
    const ok = await pollUntil(() =>
      view.evaluate<boolean>(`!!document.querySelector(${JSON.stringify(selector)})`),
    );
    if (!ok) {
      console.warn(`[sites] 列表 ${pageUrl} 等待超时(30s)，按当前 DOM 继续`);
    }
    const tExtract = performance.now();
    const snaps = await view.evaluate<AnchorSnap[]>(snapshotScript(selector));
    console.log(
      `[sites] 列表 ${pageUrl} | 等待填充 ${fmtMs(tExtract - tWait)} | 提取 ${fmtMs(performance.now() - tExtract)} | ${snaps.length} 条`,
    );
    return snaps;
  } finally {
    view.close();
  }
}

/**
 * 正文清洗脚本：在页面内对正文容器克隆加清洗，返回 { found, html }。
 * - 超链接解包（保留文字，去掉链接本身）
 * - 删除 script/style/iframe/form/视频等非正文节点
 * - 删除 class/id 带广告、推荐、分享等特征的节点
 *
 * @param containerSelector 主容器选择器
 * @param fallback 主容器未命中时的兜底表达式（页面内 IIFE，返回要清洗的节点或 null）。
 *   用于站点的次级模板（如腾讯 UTR 链接的聚合页正文不在主容器里）。
 */
export const cleanArticleScript = (
  containerSelector: string,
  fallback?: string,
) => `(() => {
  return (async () => {
    const clean = (root) => {
      for (const a of root.querySelectorAll("a")) {
        const parent = a.parentNode;
        if (!parent) continue;
        while (a.firstChild) parent.insertBefore(a.firstChild, a);
        parent.removeChild(a);
      }
      for (const n of root.querySelectorAll("script, style, iframe, form, noscript, aside, footer, nav, button, video, embed, object")) {
        n.remove();
      }
      const noiseAttr = "[class*='ad'],[class*='banner'],[class*='recommend'],[class*='related'],[class*='share'],[class*='footer'],[class*='nav'],[class*='guess'],[class*='hotlink'],[id*='ad'],[id*='banner'],[id*='recommend'],[id*='related'],[id*='share']";
      for (const n of root.querySelectorAll(noiseAttr)) n.remove();
      // 编辑器的内联排版样式（腾讯富文本大量带《style》）是纯噪声，统一去掉
      for (const n of root.querySelectorAll("[style]")) n.removeAttribute("style");
      return root.innerHTML;
    };
    const sel = ${JSON.stringify(containerSelector)};
    // 先立即尝试主容器与兜底：文章页导航完成即渲染，轮询只是防懒加载的兜底
    let el = document.querySelector(sel);
    if (el) return { found: true, html: clean(el.cloneNode(true)) };
    const fbEl = ${fallback ? `((${fallback})())` : "null"};
    if (fbEl) return { found: true, html: clean(fbEl) };
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      el = document.querySelector(sel);
      if (el) return { found: true, html: clean(el.cloneNode(true)) };
      await new Promise((r) => setTimeout(r, 300));
    }
    return { found: false, html: "" };
  })();
})()`;

/**
 * 打开文章页，等正文容器出现后进行清洗，返回正文 HTML 字符串。
 * @param pageUrl 文章 URL
 * @param containerSelector 正文容器选择器（站点各自维护，见 chinadaily.ts / tencent.ts）
 * @param fallback 主容器未命中时的兜底提取表达式（页面内 IIFE，返回节点或 null）。
 *   如腾讯 UTR 链接（专题/热点聚合文）没有主容器，正文段落是普通 <p>。
 */
export async function fetchArticleHTML(
  pageUrl: string,
  containerSelector: string,
  fallback?: string,
): Promise<string> {
  const view = new Bun.WebView({ width: 1440, height: 2000 });
  try {
    await navigateLite(view, pageUrl);
    const tWait = performance.now();
    const ok = await pollUntil(() =>
      view.evaluate<boolean>(
        `(() => {
          const sel = ${JSON.stringify(containerSelector)};
          if (document.querySelector(sel)) return true;
          return ${fallback ? `!!((${fallback})())` : "false"};
        })()`,
      ),
    );
    if (!ok) {
      console.warn(
        `[sites] 正文容器 ${containerSelector} (${pageUrl}) 等待超时(30s)，按当前 DOM 继续`,
      );
    }
    const tExtract = performance.now();
    const res = await view.evaluate<{ found: boolean; html: string }>(
      cleanArticleScript(containerSelector, fallback),
    );
    if (!res.found) {
      throw new Error(
        `文章正文容器 ${containerSelector} 在页面中未找到（兜底也未命中）: ${pageUrl}`,
      );
    }
    console.log(
      `[sites] 正文 ${pageUrl} | 等待容器 ${fmtMs(tExtract - tWait)} | 清洗 ${fmtMs(performance.now() - tExtract)} | ${res.html.length} 字节`,
    );
    return res.html;
  } finally {
    view.close();
  }
}

/** 从文章列表中随机取一篇；空列表直接抛错。 */
export function pickRandom(links: ArticleLink[]): ArticleLink {
  if (links.length === 0) {
    throw new Error("文章列表为空，无法随机选择");
  }
  return links[Math.floor(Math.random() * links.length)]!;
}

export function cleanTitle(t: string): string {
  return t.replace(/\s+/g, " ").trim();
}

export function stripQuery(href: string): string {
  return href.split("?")[0]!;
}

/** 同 URL 只保留首次出现（首页上同一文章往往出现在多个栏目展位）。 */
export function dedupe(links: ArticleLink[]): ArticleLink[] {
  const seen = new Set<string>();
  const out: ArticleLink[] = [];
  for (const l of links) {
    if (seen.has(l.url)) continue;
    seen.add(l.url);
    out.push(l);
  }
  return out;
}
