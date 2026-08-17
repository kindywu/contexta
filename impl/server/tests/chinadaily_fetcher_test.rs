//! chinadaily 驱动测试：纯解析单测（fixture）+ HTTP 集成（httpmock mock 列表页/文章页）。
//! fixture 日期动态生成（相对今天），避免测试随日期漂移失效。

use chrono::Local;
use httpmock::prelude::*;
use server::config::Config;
use server::drivers::chinadaily::{
    ChinadailyFetcher, NoopFetcher, SourceFetcher, parse_article_page, parse_list_links,
};

fn test_cfg(base_url: &str) -> Config {
    Config {
        port: 0,
        db_path: format!("/tmp/ctx-fetcher-{}.db", std::process::id()),
        jwt_secret: "test-secret".into(),
        deepseek_api_key: "sk-test".into(),
        deepseek_base_url: "https://api.deepseek.com".into(),
        deepseek_model: "deepseek-v4-flash".into(),
        word_quota_daily: 200,
        article_budget_daily: 100,
        cache_ttl_days: 30,
        cache_max_rows: 5000,
        daily_generate_hour: 3,
        admin_init_password: None,
        llm_timeout_secs: 90,
        chinadaily_base_url: base_url.into(),
        source_max_age_days: 3,
        source_fetch_timeout_secs: 15,
        recent_title_days: 14,
    }
}

/// 今天（YYYYMMDD 与 YYYY-MM-DD 两形态）。
fn today_compact() -> String {
    Local::now().format("%Y%m%d").to_string()
}

#[test]
fn parse_list_links_filters_by_age_and_formats_dates() {
    let today = Local::now().format("%Y-%m-%d").to_string();
    let two_days_ago = (Local::now() - chrono::Duration::days(2)).format("%Y-%m-%d").to_string();
    // 真实 chinadaily 文章 URL 形态：/a/YYYYMM/DD/WSxxxx.html（年月 / 日 分两段）
    let today_c = today_compact();
    let ym = today_c[0..6].to_string();
    let d = today_c[6..8].to_string();
    let two_c = (Local::now() - chrono::Duration::days(2)).format("%Y%m%d").to_string();
    let ym2 = two_c[0..6].to_string();
    let d2 = two_c[6..8].to_string();
    let html = format!(
        r#"<html>
<a href="//www.chinadaily.com.cn/a/{ym}/{d}/WSaaa.html">ok</a>
<a href="//www.chinadaily.com.cn/a/{ym}/{d}/WSaaa.html">dup url</a>
<a href="//www.chinadaily.com.cn/a/{ym2}/{d2}/WSbbb.html">2 days ago</a>
<a href="//www.chinadaily.com.cn/a/201712/12/WSccc.html">ancient</a>
<a href="//www.chinadaily.com.cn/a/{ym}/99/WSddd.html">bad day</a>
</html>"#,
    );
    let links = parse_list_links(&html, "https://www.chinadaily.com.cn", &today, 3);
    // 今天 2 条（含 1 条重复 URL——parse 层保留，fetch 层去重）+ 2 天前 1 条；
    // 2017 与非法日期被过滤。顺序 = 文档顺序（parse 层不排序）
    assert_eq!(links.len(), 3, "近 3 天 2 个 URL + 1 个重复 URL 共 3 条");
    assert_eq!(links[0].1, today);
    assert_eq!(links[1].1, today, "重复 URL 在 parse 层保留（fetch 层去重）");
    assert_eq!(links[2].1, two_days_ago);
    assert!(links.iter().all(|(u, _)| u.starts_with("https://www.chinadaily.com.cn/a/")),
        "URL 应补全基址");
}

#[test]
fn parse_article_page_extracts_title_body_and_decodes_entities() {
    let html = r#"<html><head><title>Hello World - Chinadaily.com.cn</title></head>
<body>
<p>Short.</p>
<p>This is a real paragraph with enough words to pass the minimum length filter for body text extraction.</p>
<p><strong>Second &amp; final</strong> paragraph here with more than thirty characters for sure.</p>
</body></html>"#;
    let (title, body) = parse_article_page(html).expect("应能解析");
    assert_eq!(title, "Hello World", "标题应去掉站点后缀");
    assert!(body.contains("minimum length filter"), "短段落应被过滤，长段落保留");
    assert!(body.contains("Second & final"), "HTML 实体应解码");
    assert!(body.contains("\n\n"), "段落以空行拼接");
}

#[test]
fn parse_article_page_returns_none_without_paragraphs() {
    assert!(parse_article_page("<html><title>T</title><p>short</p></html>").is_none(),
        "无长正文 → None");
}

#[test]
fn noop_fetcher_returns_empty() {
    let cfg = test_cfg("https://x");
    let r = tokio::runtime::Runtime::new().unwrap().block_on(NoopFetcher.fetch_recent(&cfg));
    assert_eq!(r.unwrap().len(), 0);
}

#[tokio::test]
async fn fetcher_parses_list_and_article_pages_over_http() {
    let server = httpmock::MockServer::start();
    let base = server.base_url();
    // 真实 chinadaily 文章 URL 形态：/a/YYYYMM/DD/WSxxxx.html（年月 / 日 分两段）
    let today_c = today_compact();
    let ym = today_c[0..6].to_string();
    let d = today_c[6..8].to_string();
    // 列表页：china 2 篇 + world 1 篇（其中 1 篇与 china 重复 URL → 去重）
    let list_china = format!(
        r#"<a href="/a/{ym}/{d}/WSa1.html">A1</a><a href="/a/{ym}/{d}/WSa2.html">A2</a>"#,
    );
    let list_world = format!(
        r#"<a href="/a/{ym}/{d}/WSa1.html">A1 dup</a><a href="/a/{ym}/{d}/WSa3.html">A3</a>"#,
    );
    let article = |id: &str| {
        format!(
            r#"<html><title>Article {id} - Chinadaily.com.cn</title><body>
<p>This is the body paragraph of article {id} with plenty of words to pass the extraction filter.</p></body></html>"#
        )
    };
    for (section, body) in [("china", &list_china), ("world", &list_world)] {
        server.mock(|when, then| {
            when.method(GET).path(format!("/{section}"));
            then.status(200).body(body.as_str());
        });
    }
    for id in ["WSa1", "WSa2", "WSa3"] {
        server.mock(|when, then| {
            when.method(GET).path(format!("/a/{ym}/{d}/{id}.html"));
            then.status(200).body(article(id).as_str());
        });
    }
    let cfg = test_cfg(&base);
    let fetcher = ChinadailyFetcher::new(&cfg).unwrap();
    let sources = fetcher.fetch_recent(&cfg).await.unwrap();
    assert_eq!(sources.len(), 3, "china 2 + world 1，重复 URL 去重");
    assert_eq!(sources[0].url, format!("{base}/a/{ym}/{d}/WSa1.html"));
    assert_eq!(sources[0].title, "Article WSa1");
    assert!(sources[0].body.contains("body paragraph"));
    assert_eq!(sources[0].published_at, Local::now().format("%Y-%m-%d").to_string());
}

#[tokio::test]
async fn fetcher_propagates_list_page_error() {
    let server = httpmock::MockServer::start();
    server.mock(|when, then| {
        when.method(GET).path("/china");
        then.status(500);
    });
    server.mock(|when, then| {
        when.method(GET).path("/world");
        then.status(500);
    });
    let cfg = test_cfg(&server.base_url());
    let fetcher = ChinadailyFetcher::new(&cfg).unwrap();
    let r = fetcher.fetch_recent(&cfg).await;
    assert!(r.is_err(), "列表页 500 应整体报错（由降级路径消费）");
}
