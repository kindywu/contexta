//! chinadaily 事实源驱动（NEWS 分类事实锚定）：抓取近期文章（栏目列表页 → 文章页正文）。
//! 纯解析函数与 HTTP IO 分离（fixture 可单测，测试注入 mock fetcher）。
//!
//! 弃 RSS 原因：chinadaily RSS（/rss/*.xml）内容停留在 2017-12，实测已弃用多年——只能抓 HTML。
//! 列表页链接路径自带日期（/a/202608/17/WS...html），以此过滤新鲜度，无需额外日期请求。

use async_trait::async_trait;
use chrono::{Duration, NaiveDate};
use regex::Regex;
use std::sync::OnceLock;

use crate::config::Config;

/// 抓取产物：一篇可作事实源的 chinadaily 文章。
#[derive(Debug, Clone)]
pub struct FetchedSource {
    pub url: String,
    pub title: String,
    pub body: String,
    pub published_at: String, // YYYY-MM-DD（URL 路径日期）
}

/// 事实源抓取接口：生成管线只依赖本 trait（测试注入 mock）。
#[async_trait]
pub trait SourceFetcher: Send + Sync {
    async fn fetch_recent(&self, cfg: &Config) -> Result<Vec<FetchedSource>, anyhow::Error>;
}

/// 空抓取器：构造失败降级 / 测试默认——恒返回空（NEWS 走自由发挥降级）。
pub struct NoopFetcher;
#[async_trait]
impl SourceFetcher for NoopFetcher {
    async fn fetch_recent(&self, _cfg: &Config) -> Result<Vec<FetchedSource>, anyhow::Error> {
        Ok(Vec::new())
    }
}

/// 抓取的栏目列表页（来源池更宽，两个栏目都抓）。
const SECTIONS: [&str; 2] = ["china", "world"];
/// 每轮抓正文的文章数上限（控制请求成本；池内优先最新）。
const MAX_BODY_FETCH: usize = 20;
/// 正文最大长度（字符，控制 prompt 注入体积）。
const MAX_BODY_CHARS: usize = 4000;

pub struct ChinadailyFetcher {
    http: reqwest::Client,
}

impl ChinadailyFetcher {
    pub fn new(cfg: &Config) -> anyhow::Result<Self> {
        Ok(Self {
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(cfg.source_fetch_timeout_secs))
                .build()?,
        })
    }
}

#[async_trait]
impl SourceFetcher for ChinadailyFetcher {
    async fn fetch_recent(&self, cfg: &Config) -> Result<Vec<FetchedSource>, anyhow::Error> {
        let base = cfg.chinadaily_base_url.trim_end_matches('/').to_string();
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        let mut links: Vec<(String, String)> = Vec::new();
        for section in SECTIONS {
            let html = self
                .http
                .get(format!("{base}/{section}"))
                .send()
                .await?
                .error_for_status()?
                .text()
                .await?;
            links.extend(parse_list_links(&html, &base, &today, cfg.source_max_age_days));
        }
        // 去重（seen 集合，保留首次出现）后按日期降序（最新的先抓）。dedup_by 只移除
        // 相邻重复——同日多篇时同 URL 不相邻，不可靠；同日多篇顺序稳定保留（先 china 后 world）。
        let mut seen = std::collections::HashSet::new();
        links.retain(|(url, _)| seen.insert(url.clone()));
        links.sort_by(|a, b| b.1.cmp(&a.1));
        let mut out = Vec::new();
        for (url, date) in links.into_iter().take(MAX_BODY_FETCH) {
            let html = match self.http.get(&url).send().await {
                Ok(r) => match r.error_for_status() {
                    Ok(r) => r.text().await.unwrap_or_default(),
                    Err(e) => {
                        tracing::warn!("chinadaily article {url}: {e}");
                        continue;
                    }
                },
                Err(e) => {
                    tracing::warn!("chinadaily article {url}: {e}");
                    continue;
                }
            };
            match parse_article_page(&html) {
                Some((title, body)) => out.push(FetchedSource {
                    url,
                    title,
                    body,
                    published_at: date,
                }),
                None => tracing::warn!("chinadaily article unparseable: {url}"),
            }
        }
        Ok(out)
    }
}

/// 列表页解析：提取近 [max_age_days] 天内文章链接 → (完整 URL, YYYY-MM-DD)。
/// 纯函数（today 显式传入），fixture 可单测。链接路径 `/a/YYYYMM/DD/WSxxx.html` 自带发布日。
pub fn parse_list_links(
    html: &str,
    base: &str,
    today: &str,
    max_age_days: i64,
) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let Ok(today_d) = NaiveDate::parse_from_str(today, "%Y-%m-%d") else {
        return out;
    };
    let min = today_d - Duration::days(max_age_days);
    for cap in link_re().captures_iter(html) {
        let Ok(y) = cap[1].parse::<i32>() else { continue };
        let Ok(m) = cap[2].parse::<u32>() else { continue };
        let Ok(d) = cap[3].parse::<u32>() else { continue };
        let Some(date) = NaiveDate::from_ymd_opt(y, m, d) else { continue };
        if date < min || date > today_d {
            continue; // 超出新鲜窗口（或未来日期）跳过
        }
        out.push((
            format!("{}{}", base.trim_end_matches('/'), &cap[0]),
            date.format("%Y-%m-%d").to_string(),
        ));
    }
    out
}

/// 文章页解析：提取 (title 去站点后缀, 正文纯文本)。<p> 文本拼接，短片段（导航/广告）过滤。
/// 失败（无 title / 无正文）→ None。
pub fn parse_article_page(html: &str) -> Option<(String, String)> {
    let title = title_re()
        .captures(html)?
        .get(1)?
        .as_str()
        .trim()
        .trim_end_matches(" - Chinadaily.com.cn")
        .to_string();
    let mut paras: Vec<String> = Vec::new();
    for cap in p_re().captures_iter(html) {
        let Some(inner) = cap.get(1) else { continue };
        let txt = strip_tags(inner.as_str());
        let txt = txt.split_whitespace().collect::<Vec<_>>().join(" ");
        if txt.chars().count() >= 30 {
            paras.push(txt);
        }
    }
    if paras.is_empty() {
        return None;
    }
    let body: String = paras.join("\n\n").chars().take(MAX_BODY_CHARS).collect();
    if title.is_empty() {
        return None;
    }
    Some((title, body))
}

/// 去除 HTML 标签 + 最小实体解码（&amp; 放首位避免二次解码）。
fn strip_tags(s: &str) -> String {
    let s = tag_re().replace_all(s, "");
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
}

fn link_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"/a/(20\d{2})(\d{2})/(\d{2})/WS[0-9a-fA-F]+\.html").unwrap())
}
fn title_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?is)<title>(.*?)</title>").unwrap())
}
fn p_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?is)<p[^>]*>(.*?)</p>").unwrap())
}
fn tag_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?is)<[^>]+>").unwrap())
}
