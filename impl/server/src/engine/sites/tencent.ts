/**
 * 腾讯新闻（news.qq.com）：SiteFetcher 实现。
 * 解析规则与其他站点不同（三种标题结构 + .rich_media_content 正文容器），
 * 外界统一经由 sites/index.ts 的工厂访问。
 */
import {
  dedupe,
  fetchAnchorSnapshots,
  fetchArticleHTML,
  stripQuery,
  cleanTitle,
  type AnchorSnap,
  type ArticleLink,
  type SiteFetcher,
} from "./common";

/** 腾讯新闻链接：/rain/a/<id>（资讯）或 view.inews.qq.com/a/<id>（深度/企鹅号）。 */
const TENCENT_LINK_RE = /(?:news\.qq\.com|view\.inews\.qq\.com)\//;

/** 腾讯标题里会混入“专题/实时播报”标签、来源和时间，逐个剥离。 */
const TENCENT_LABEL_RE = /^(?:专题|实时播报|热点精选|快讯|独家|深度|视频)\s*/;

/** 正文容器 class（探针确认：正文在 .rich_media_content 内，含尾部来源标注与内联样式）。 */
const CONTENT_SELECTOR = ".rich_media_content";

/**
 * UTR 链接（专题/热点聚合文）没有 .rich_media_content：正文是页面中
 * 文本较长的普通 <p> 段落，且不在评论区/推荐区。
 * 兜底：取最长 <p>，向上合并到段落的公共包装层（父级子元素少、文本量小的
 * 小容器就继续上爬，直到接近正文区块）。
 */
const FALLBACK_CONTENT_SCRIPT = `() => {
  const scope = document.querySelector("article, main, #root") ?? document.body;
  const ps = [...scope.querySelectorAll("p")].filter((p) => {
    const t = (p.textContent ?? "").trim();
    return t.length > 60 &&
      !p.closest("[class*='comment'], [class*='recommend'], [class*='footer'], [class*='nav']");
  });
  if (ps.length === 0) return null;
  ps.sort((a, b) => (b.textContent ?? "").length - (a.textContent ?? "").length);
  let el = ps[0];
  while (
    el.parentElement &&
    el.parentElement !== scope &&
    el.parentElement.children.length <= 3 &&
    (el.parentElement.textContent ?? "").length < 8000
  ) {
    el = el.parentElement;
  }
  return el;
}`;

/** 腾讯提取规则：按结构取标题（剥标签/来源/时间），URL 去 query 后去重保序。 */
export function extractTencentNewsLinks(snaps: AnchorSnap[]): ArticleLink[] {
  const links: ArticleLink[] = [];
  for (const s of snaps) {
    if (!TENCENT_LINK_RE.test(s.href)) continue; // 与页面选择器一致的双重保险
    let title: string;
    if (s.cls.includes("article-base-info")) {
      // [标签, 标题, 来源+时间]
      title = s.childTexts[1] ?? s.childTexts.at(-1) ?? s.text;
    } else if (s.cls.includes("article-title")) {
      // [标签, 标题] 或 [标题]
      title = s.childTexts[1] ?? s.childTexts.at(-1) ?? s.text;
    } else {
      title = s.text;
    }
    title = cleanTitle(title.replace(TENCENT_LABEL_RE, ""));
    if (!title) continue; // 图片位锚点（无文字）跳过
    links.push({ title, url: stripQuery(s.href) });
  }
  return dedupe(links);
}

export const tencent: SiteFetcher = {
  name: "tencent",
  async fetchLinks(homeUrl: string): Promise<ArticleLink[]> {
    const snaps = await fetchAnchorSnapshots(
      homeUrl,
      'a[href*="rain/a/"], a[href*="view.inews.qq.com/a/"]',
    );
    return extractTencentNewsLinks(snaps);
  },
  async fetchArticle(link) {
    return {
      title: link.title,
      url: link.url,
      html: await fetchArticleHTML(link.url, CONTENT_SELECTOR, FALLBACK_CONTENT_SCRIPT),
    };
  },
};
