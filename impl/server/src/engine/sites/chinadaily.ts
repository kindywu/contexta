/**
 * 中国日报（www.chinadaily.com.cn）：SiteFetcher 实现。
 * 解析规则与其他站点不同（URL 模式 + 近 30 天 + #Content 正文容器），
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

/** 中国日报文章页 URL 形如 /a/202608/28/WS6a90c54a....html */
const CD_ARTICLE_RE = /chinadaily\.com\.cn\/a\/(\d{4})(\d{2})\/\d{2}\/WS[0-9a-f]+\.html/;
/** 首页只保留最近 30 天内的文章链接（排除年代久远的栏目锚点页）。 */
const CD_RECENT_MS = 30 * 24 * 3600_000;

/** 正文容器 id（探针确认：整个文章区在 #Content 内，无 script/iframe/广告节点）。 */
const CONTENT_SELECTOR = "#Content";

/** 中国日报提取规则：URL 模式 + 近 30 天 + 去空白标题，按 URL 去重保序。 */
export function extractChinaDailyLinks(snaps: AnchorSnap[]): ArticleLink[] {
  const cutoff = Date.now() - CD_RECENT_MS;
  const links: ArticleLink[] = [];
  for (const s of snaps) {
    const m = s.href.match(CD_ARTICLE_RE);
    if (!m) continue;
    const monthStart = new Date(Number(m[1]!), Number(m[2]!) - 1, 1);
    if (monthStart.getTime() < cutoff) continue; // 栏目锚点页（2017~2024 的旧链接）直接跳过
    const title = cleanTitle(s.text);
    if (!title) continue;
    links.push({ title, url: stripQuery(s.href) });
  }
  return dedupe(links);
}

export const chinadaily: SiteFetcher = {
  name: "chinadaily",
  async fetchLinks(homeUrl: string): Promise<ArticleLink[]> {
    const snaps = await fetchAnchorSnapshots(
      homeUrl,
      'a[href*="chinadaily.com.cn/a/"]',
    );
    return extractChinaDailyLinks(snaps);
  },
  async fetchArticle(link) {
    return {
      title: link.title,
      url: link.url,
      html: await fetchArticleHTML(link.url, CONTENT_SELECTOR),
    };
  },
};
