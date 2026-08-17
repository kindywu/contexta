//! 事实源服务（NEWS 分类事实锚定）：抓取产物入库（URL 唯一幂等）、选源（单语句条件更新
//! 预占，与 T8 预占行模式同纪律——并发安全，is_used=1 即在 LLM 调用前占用）。
//! 池空 → 抓取补充 → 再选；抓取失败降级 Ok(None)（生成任务不因无源停摆，自由发挥兜底）。
//! is_used 与 article.source_article_id 冗余的决策记录（db:NF）：is_used 是"可用性"状态，
//! 需要单语句条件更新保证并发选中原子性；source_article_id 是"谁用了它"的引用记录，职责不同。

use crate::config::Config;
use crate::drivers::chinadaily::{FetchedSource, SourceFetcher};
use crate::response::AppError;
use chrono::{Duration, Local, Utc};
use sqlx::SqlitePool;

/// 一篇已被选中的事实源（含正文，供 prompt 注入；LLM 调用前占用）。
pub struct SourceArticle {
    pub id: i64,
    pub url: String,
    pub title: String,
    pub body: String,
    pub published_at: String,
}

/// 抓取产物入库：URL UNIQUE + INSERT OR IGNORE 幂等（重复抓取无副作用）。返回新插入行数。
pub async fn store_sources(pool: &SqlitePool, fetched: Vec<FetchedSource>) -> Result<usize, AppError> {
    let now = Utc::now().timestamp_millis();
    let mut n: usize = 0;
    for s in fetched {
        let r = sqlx::query(
            "INSERT OR IGNORE INTO article_source (source_url, title, body, published_at, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&s.url)
        .bind(&s.title)
        .bind(&s.body)
        .bind(&s.published_at)
        .bind(now)
        .bind(now)
        .execute(pool)
        .await?;
        n += r.rows_affected() as usize;
    }
    Ok(n)
}

/// 选源：池内未用来源 → 单语句条件更新预占（affected=1 才占用，并发冲突换下一行，至多 3 次）。
/// 池空 → 抓取补充（失败记 warn 降级 Ok(None)，不阻断生成）→ 再选。
pub async fn pick_source(
    pool: &SqlitePool,
    cfg: &Config,
    fetcher: &dyn SourceFetcher,
) -> Result<Option<SourceArticle>, AppError> {
    if let Some(s) = try_pick(pool, cfg).await? {
        return Ok(Some(s));
    }
    match fetcher.fetch_recent(cfg).await {
        Ok(fetched) => {
            store_sources(pool, fetched).await?;
            try_pick(pool, cfg).await
        }
        Err(e) => {
            tracing::warn!("chinadaily fetch failed, degrade to free-write: {e}");
            Ok(None)
        }
    }
}

async fn try_pick(pool: &SqlitePool, cfg: &Config) -> Result<Option<SourceArticle>, AppError> {
    let min_date = (Local::now() - Duration::days(cfg.source_max_age_days))
        .format("%Y-%m-%d")
        .to_string();
    for _ in 0..3 {
        let row: Option<(i64, String, String, String, String)> = sqlx::query_as(
            "SELECT id, source_url, title, body, published_at FROM article_source
             WHERE is_used = 0 AND is_deleted = 0 AND published_at >= ?
             ORDER BY published_at DESC, id DESC LIMIT 1",
        )
        .bind(&min_date)
        .fetch_optional(pool)
        .await?;
        let Some((id, url, title, body, published_at)) = row else {
            return Ok(None);
        };
        let now = Utc::now().timestamp_millis();
        let n = sqlx::query(
            "UPDATE article_source SET is_used = 1, updated_at = ? WHERE id = ? AND is_used = 0",
        )
        .bind(now)
        .bind(id)
        .execute(pool)
        .await?
        .rows_affected();
        if n == 1 {
            return Ok(Some(SourceArticle {
                id,
                url,
                title,
                body,
                published_at,
            }));
        }
        // 并发下被另一路占用：重试下一行
    }
    Ok(None)
}
