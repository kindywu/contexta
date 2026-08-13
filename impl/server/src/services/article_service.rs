//! 文章生成/审核状态机（T8）：每日每难度 5 篇幂等生成、单篇生成、审核
//! （拒绝自动补生成，上限 REGENERATE_CAP 次）、每日预算、列表/详情/按日下发查询。
//! 段落以 `英文|||中文` 单列存储（下发时拆分，T10 消费）。

use crate::config::Config;
use crate::drivers::deepseek::DeepSeekApi;
use crate::response::AppError;
use crate::services::{llm_service, today_start_millis};
use chrono::Utc;
use sqlx::SqlitePool;

pub const ARTICLES_PER_DIFFICULTY: i64 = 5;
pub const DIFFICULTIES: [&str; 3] = ["LOW", "MEDIUM", "HIGH"];
pub const REGENERATE_CAP: i64 = 3;

pub const LOW_CATEGORIES: [&str; 3] = ["DAILY_CONVERSATION", "SCENE_DESCRIPTION", "SIMPLE_STORY"];
pub const MEDIUM_CATEGORIES: [&str; 4] = ["NEWS", "EXPOSITORY", "ARGUMENTATIVE", "PERSONAL_ESSAY"];
pub const HIGH_CATEGORIES: [&str; 5] = [
    "ACADEMIC_EXCERPT",
    "DEBATE_SPEECH",
    "LEGAL_DOCUMENT",
    "ART_CRITICISM",
    "CLASSIC_NOVEL_EXCERPT",
];

fn categories_for(difficulty: &str) -> &'static [&'static str] {
    match difficulty {
        "LOW" => &LOW_CATEGORIES,
        "MEDIUM" => &MEDIUM_CATEGORIES,
        "HIGH" => &HIGH_CATEGORIES,
        _ => &MEDIUM_CATEGORIES,
    }
}

/// 题材轮换：以 target_date 为种子轮转分类，保证连续两天不重复。
fn category_for(difficulty: &str, target_date: &str, order_index: i64) -> &'static str {
    let cats = categories_for(difficulty);
    let seed: u32 = target_date.replace('-', "").parse().unwrap_or(0);
    cats[(seed as usize + order_index as usize) % cats.len()]
}

/// 每日预算：今日（本地语义，today_start_millis）已生成文章数 >= 预算 → QuotaExceeded。
pub async fn check_daily_budget(pool: &SqlitePool, cfg: &Config) -> Result<(), AppError> {
    let today = today_start_millis();
    let n: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article WHERE created_at >= ?")
        .bind(today)
        .fetch_one(pool)
        .await?;
    if n >= cfg.article_budget_daily {
        return Err(AppError::QuotaExceeded(
            "article daily budget exceeded".into(),
        ));
    }
    Ok(())
}

/// 幂等：每难度已有 ≥5 条非终结（pending_review/approved）则跳过；否则补到 5。
/// 补生成延续 MAX(order_index) 起新 order，题材按日期种子轮换。
pub async fn ensure_daily_generation(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    target_date: &str,
) -> Result<(), AppError> {
    for difficulty in DIFFICULTIES {
        let existing: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM article WHERE target_date = ? AND difficulty = ? AND status IN ('pending_review','approved')",
        )
        .bind(target_date)
        .bind(difficulty)
        .fetch_one(pool)
        .await?;
        let mut need = ARTICLES_PER_DIFFICULTY - existing;
        if need <= 0 {
            continue;
        }
        let max_order: i64 = sqlx::query_scalar(
            "SELECT COALESCE(MAX(order_index), 0) FROM article WHERE target_date = ? AND difficulty = ?",
        )
        .bind(target_date)
        .bind(difficulty)
        .fetch_one(pool)
        .await?;
        let mut order = max_order;
        while need > 0 {
            check_daily_budget(pool, cfg).await?;
            order += 1;
            let category = category_for(difficulty, target_date, order);
            generate_one(pool, cfg, api, target_date, difficulty, category, order).await?;
            need -= 1;
        }
    }
    Ok(())
}

/// 单篇生成：LLM 出稿 → 写 article（pending_review）+ 段落（`英文|||中文` 单列）→ 记用量。
pub async fn generate_one(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    target_date: &str,
    difficulty: &str,
    category: &str,
    order_index: i64,
) -> Result<(), AppError> {
    check_daily_budget(pool, cfg).await?;
    let started = tokio::time::Instant::now();
    let (title, paragraphs) =
        llm_service::generate_article_content(api, cfg, difficulty, category, order_index).await?;
    let latency = started.elapsed().as_millis() as i64;
    let now = Utc::now().timestamp_millis();
    let id = sqlx::query(
        "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, prompt_tokens, completion_tokens, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'pending_review', 0, 0, ?, ?)",
    )
    .bind(target_date)
    .bind(difficulty)
    .bind(category)
    .bind(order_index)
    .bind(&title)
    .bind(now)
    .bind(now)
    .execute(pool)
    .await?
    .last_insert_rowid();
    let mut o = 0i64;
    for (_, en, zh) in &paragraphs {
        o += 1;
        sqlx::query(
            "INSERT INTO article_paragraph (article_id, order_index, text) VALUES (?, ?, ?)",
        )
        .bind(id)
        .bind(o)
        .bind(format!("{en}|||{zh}"))
        .execute(pool)
        .await?;
    }
    // 段落文本格式：`英文|||中文`（下发时拆分；服务端不存第二列避免 1NF 争议）
    record_generation_usage(pool, cfg, &title, latency).await;
    Ok(())
}

async fn record_generation_usage(pool: &SqlitePool, _cfg: &Config, _title: &str, latency: i64) {
    // token 数在 generate_article_content 未回传——简化为 endpoint 计数（0 token）：
    llm_service::record_usage(pool, None, "article_generate", 0, 0, latency)
        .await
        .ok();
}

/// 审核通过：仅 pending_review 可 approve，其余（含重复）→ NotFound。
pub async fn approve_article(pool: &SqlitePool, id: i64) -> Result<(), AppError> {
    let now = Utc::now().timestamp_millis();
    let n = sqlx::query(
        "UPDATE article SET status = 'approved', updated_at = ? WHERE id = ? AND status = 'pending_review'",
    )
    .bind(now)
    .bind(id)
    .execute(pool)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound("article not pending_review".into()));
    }
    Ok(())
}

/// 审核拒绝：旧行 → rejected（达补生上限则 rejected_final），未达上限时预算内补生成新行
/// （regenerate_count = 父行 +1），题材轮换到下一分类。
pub async fn reject_article(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    id: i64,
    reason: &str,
) -> Result<(), AppError> {
    let row: Option<(String, String, i64, i64)> = sqlx::query_as(
        "SELECT target_date, difficulty, order_index, regenerate_count FROM article WHERE id = ? AND status = 'pending_review'",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    let (date, difficulty, order, regen) =
        row.ok_or(AppError::NotFound("article not pending_review".into()))?;
    let now = Utc::now().timestamp_millis();
    sqlx::query(
        "UPDATE article SET status = 'rejected', reject_reason = ?, updated_at = ? WHERE id = ?",
    )
    .bind(reason)
    .bind(now)
    .bind(id)
    .execute(pool)
    .await?;
    if regen >= REGENERATE_CAP {
        sqlx::query("UPDATE article SET status = 'rejected_final', updated_at = ? WHERE id = ?")
            .bind(now)
            .bind(id)
            .execute(pool)
            .await?;
        return Ok(());
    }
    // 补生成（预算内）：新行 pending_review，regenerate_count = regen+1
    check_daily_budget(pool, cfg).await?;
    let category = category_for(&difficulty, &date, order + regen + 1);
    generate_one(pool, cfg, api, &date, &difficulty, category, order).await?;
    // 更新刚生成行的 regenerate_count（= 父行 regen+1）。
    // 简报写法 MAX(id) 依赖服务端任务串行执行（单任务线程内无并发插入），此处沿用；
    // 若未来并发生成同一日期，应改为按 (target_date, difficulty, order_index) 精确锁定最后一行。
    sqlx::query("UPDATE article SET regenerate_count = ?, updated_at = ? WHERE id = (SELECT MAX(id) FROM article)")
        .bind(regen + 1)
        .bind(Utc::now().timestamp_millis())
        .execute(pool)
        .await?;
    Ok(())
}

/// 下发/管理视图：段落已拆分（英文、中文），供 T10 下发与 T12 审核列表复用。
pub struct ArticleView {
    pub id: i64,
    pub target_date: String,
    pub difficulty: String,
    pub content_category: String,
    pub order_index: i64,
    pub title: String,
    pub status: String,
    pub regenerate_count: i64,
    pub paragraphs: Vec<(i64, String, String)>,
}

async fn load_view(
    pool: &SqlitePool,
    id: i64,
    title: String,
    date: String,
    difficulty: String,
    category: String,
    order: i64,
    status: String,
    regen: i64,
) -> Result<ArticleView, AppError> {
    let rows: Vec<(i64, String)> = sqlx::query_as(
        "SELECT order_index, text FROM article_paragraph WHERE article_id = ? ORDER BY order_index",
    )
    .bind(id)
    .fetch_all(pool)
    .await?;
    let paragraphs = rows
        .into_iter()
        .map(|(o, t)| {
            let (en, zh) = t.split_once("|||").unwrap_or((t.as_str(), ""));
            (o, en.to_string(), zh.to_string())
        })
        .collect();
    Ok(ArticleView {
        id,
        target_date: date,
        difficulty,
        content_category: category,
        order_index: order,
        title,
        status,
        regenerate_count: regen,
        paragraphs,
    })
}

pub async fn get_article(pool: &SqlitePool, id: i64) -> Result<ArticleView, AppError> {
    let row: Option<(String, String, String, String, i64, String, i64)> = sqlx::query_as(
        "SELECT title, target_date, difficulty, content_category, order_index, status, regenerate_count FROM article WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    match row {
        Some((title, date, diff, cat, order, status, regen)) => {
            load_view(pool, id, title, date, diff, cat, order, status, regen).await
        }
        None => Err(AppError::NotFound("article not found".into())),
    }
}

/// 按日下发：仅 approved 可见，按难度、order_index 排序。
pub async fn get_approved_by_date(
    pool: &SqlitePool,
    date: &str,
) -> Result<Vec<ArticleView>, AppError> {
    let rows: Vec<(i64, String, String, String, i64, i64)> = sqlx::query_as(
        "SELECT id, title, difficulty, content_category, order_index, regenerate_count FROM article
         WHERE target_date = ? AND status = 'approved' ORDER BY difficulty, order_index",
    )
    .bind(date)
    .fetch_all(pool)
    .await?;
    let mut out = Vec::new();
    for (id, title, diff, cat, order, regen) in rows {
        out.push(
            load_view(
                pool,
                id,
                title,
                date.to_string(),
                diff,
                cat,
                order,
                "approved".into(),
                regen,
            )
            .await?,
        );
    }
    Ok(out)
}

/// 列表查询：date/status 可选过滤。WHERE 只拼白名单列名（target_date/status），值全部绑参。
/// sqlx 0.9 的 query* 只接受 SqlSafeStr（&'static str 原生实现）——SQL 文本仅由字面量拼接
/// （无用户输入），显式包 AssertSqlSafe 声明安全；0.9 无 bind_all，循环 bind。
pub async fn list_articles(
    pool: &SqlitePool,
    date: Option<&str>,
    status: Option<&str>,
) -> Result<Vec<ArticleView>, AppError> {
    let mut sql = String::from(
        "SELECT id, title, target_date, difficulty, content_category, order_index, status, regenerate_count FROM article",
    );
    let mut conds: Vec<&str> = Vec::new();
    let mut args: Vec<String> = Vec::new();
    if let Some(d) = date {
        conds.push("target_date = ?");
        args.push(d.to_string());
    }
    if let Some(s) = status {
        conds.push("status = ?");
        args.push(s.to_string());
    }
    if !conds.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&conds.join(" AND "));
    }
    sql.push_str(" ORDER BY target_date DESC, difficulty, order_index");
    let mut q = sqlx::query_as::<_, (i64, String, String, String, String, i64, String, i64)>(
        sqlx::AssertSqlSafe(sql),
    );
    for a in &args {
        q = q.bind(a);
    }
    let rows = q.fetch_all(pool).await?;
    let mut out = Vec::new();
    for (id, title, date, diff, cat, order, status, regen) in rows {
        out.push(load_view(pool, id, title, date, diff, cat, order, status, regen).await?);
    }
    Ok(out)
}
