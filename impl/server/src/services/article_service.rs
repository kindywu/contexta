//! 文章生成/审核状态机（T8）：每日每难度 5 篇幂等生成、单篇生成、审核
//! （拒绝自动补生成，上限 REGENERATE_CAP 次）、每日预算、列表/详情/按日下发查询。
//! 段落以 `英文|||中文` 单列存储（下发时拆分，T10 消费）。

use crate::config::Config;
use crate::drivers::deepseek::DeepSeekApi;
use crate::response::AppError;
use crate::services::{llm_service, today_start_millis};
use chrono::{Datelike, NaiveDate, Utc};
use sqlx::{SqliteConnection, SqlitePool};

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

/// 题材轮换：以 target_date 的 epoch 天数（自 0001-01-01 起，连续两天恒差 1）为种子轮转分类，
/// 相邻两天同一 order 的分类 mod 3/4/5 均不碰撞——保证连续两天不重复。
/// （yyyyMMdd 数字种子在 31 天月末差 70、年末差 8870，对 HIGH 的 mod 5 撞 0，会连续两天同分类，弃用。）
/// 同日补生成（reject 重试）以 order+regen+1 轮换到下一分类；LOW 仅 3 类而上限 3 次补生成
/// （共 4 代），第 4 代必然回到原分类——同日同类可重复，属 3 类 4 代固有行为，非种子缺陷。
fn category_for(difficulty: &str, target_date: &str, order_index: i64) -> &'static str {
    let cats = categories_for(difficulty);
    let seed = NaiveDate::parse_from_str(target_date, "%Y-%m-%d")
        .map(|d| d.num_days_from_ce())
        .unwrap_or(0);
    cats[(seed as usize + order_index as usize) % cats.len()]
}

/// 每日预算：今日（本地语义，today_start_millis）已生成文章数 >= 预算 → QuotaExceeded。
/// executor 泛型：事务内（ensure_daily_generation）须用事务连接计数（含本事务未提交行），
/// 事务外（reject 补生成 / 外部调用）传 &SqlitePool。
pub async fn check_daily_budget<'e, E>(exec: E, cfg: &Config) -> Result<(), AppError>
where
    E: sqlx::Executor<'e, Database = sqlx::Sqlite>,
{
    let today = today_start_millis();
    let n: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM article WHERE created_at >= ?")
        .bind(today)
        .fetch_one(exec)
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
///
/// 并发安全（审查修复）：整个「查 existing + 生成循环」包进 BEGIN IMMEDIATE 事务——
/// SQLite 单写者下并发的 ensure 调用（T9 定时 + 手动触发）在 BEGIN 处排队，后到者的计数
/// 必然发生在先到者 COMMIT 之后，不会双生成。sqlx 默认 begin() 是 DEFERRED（先 SELECT 后
/// INSERT 的窗口内两会话同见 0），故用 begin_with 显式指定 IMMEDIATE；出错时 tx 自动回滚
/// （sqlx Transaction drop 语义），全批不落半成品。
pub async fn ensure_daily_generation(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    target_date: &str,
) -> Result<(), AppError> {
    let mut tx = pool.begin_with("BEGIN IMMEDIATE").await?;
    for difficulty in DIFFICULTIES {
        let existing: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM article WHERE target_date = ? AND difficulty = ? AND status IN ('pending_review','approved')",
        )
        .bind(target_date)
        .bind(difficulty)
        .fetch_one(&mut *tx)
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
        .fetch_one(&mut *tx)
        .await?;
        let mut order = max_order;
        while need > 0 {
            check_daily_budget(&mut *tx, cfg).await?;
            order += 1;
            let category = category_for(difficulty, target_date, order);
            generate_conn(&mut tx, cfg, api, target_date, difficulty, category, order).await?;
            need -= 1;
        }
    }
    tx.commit().await?;
    Ok(())
}

/// 单篇生成（pool 入口）：预算校验 + LLM 出稿 + 落库 + 记用量，返回新行 id。
/// 返回 id 供 reject_article 精确对补生成行记账（审查修复：不再依赖 MAX(id)）。
pub async fn generate_one(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    target_date: &str,
    difficulty: &str,
    category: &str,
    order_index: i64,
) -> Result<i64, AppError> {
    let mut conn = pool.acquire().await?;
    generate_conn(
        &mut conn,
        cfg,
        api,
        target_date,
        difficulty,
        category,
        order_index,
    )
    .await
}

/// 在指定连接上执行单篇生成：预算校验 + LLM 出稿 → 写 article（pending_review，
/// prompt/completion_tokens 记真值）+ 段落（`英文|||中文` 单列）→ 记用量（真值 token）。
/// 事务内（ensure_daily_generation）与单发（generate_one）共用；返回新行 id。
async fn generate_conn(
    conn: &mut SqliteConnection,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    target_date: &str,
    difficulty: &str,
    category: &str,
    order_index: i64,
) -> Result<i64, AppError> {
    check_daily_budget(&mut *conn, cfg).await?;
    let started = tokio::time::Instant::now();
    let (title, paragraphs, prompt_tokens, completion_tokens) =
        llm_service::generate_article_content(api, cfg, difficulty, category, order_index).await?;
    let latency = started.elapsed().as_millis() as i64;
    let now = Utc::now().timestamp_millis();
    let id = sqlx::query(
        "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, prompt_tokens, completion_tokens, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'pending_review', ?, ?, ?, ?)",
    )
    .bind(target_date)
    .bind(difficulty)
    .bind(category)
    .bind(order_index)
    .bind(&title)
    .bind(prompt_tokens as i64)
    .bind(completion_tokens as i64)
    .bind(now)
    .bind(now)
    .execute(&mut *conn)
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
        .execute(&mut *conn)
        .await?;
    }
    // 段落文本格式：`英文|||中文`（下发时拆分；服务端不存第二列避免 1NF 争议）
    // 用量记账失败不阻断生成（成本统计尽力而为，不因 usage_log 问题丢弃已生成的稿件）
    llm_service::record_usage(
        &mut *conn,
        None,
        "article_generate",
        prompt_tokens,
        completion_tokens,
        latency,
    )
    .await
    .ok();
    Ok(id)
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
    // 补生成（预算内）：新行 pending_review，regenerate_count = 父行 regen+1。
    // 审查修复：generate_one 返回新行 id，直接对刚生成行记账——
    // 不再用 MAX(id)（INSERT 与 UPDATE 之间有 await 点，并发下 MAX(id) 可能命中错行）。
    check_daily_budget(pool, cfg).await?;
    let category = category_for(&difficulty, &date, order + regen + 1);
    let new_id = generate_one(pool, cfg, api, &date, &difficulty, category, order).await?;
    sqlx::query("UPDATE article SET regenerate_count = ?, updated_at = ? WHERE id = ?")
        .bind(regen + 1)
        .bind(Utc::now().timestamp_millis())
        .bind(new_id)
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
