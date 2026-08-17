//! 文章生成/审核状态机（T8）：每日每难度 5 篇幂等生成、单篇生成、审核
//! （拒绝自动补生成，上限 REGENERATE_CAP 次）、每日预算、列表/详情/按日下发查询。
//! 段落以 `英文|||中文` 单列存储（下发时拆分，T10 消费）。
//!
//! 预占行模式（审查重构）：生成 = 短事务预留（预占行，title NULL）→ 锁外 LLM 填充。
//! 状态机：pending_review（预占/已生成）→ approved / rejected / rejected_final / failed；
//! failed（生成失败，title 仍 NULL）不计入非终结，下次 ensure 补预占行替换。

use crate::config::Config;
use crate::drivers::chinadaily::SourceFetcher;
use crate::drivers::deepseek::DeepSeekApi;
use crate::response::AppError;
use crate::services::{llm_service, source_service, today_start_millis};
use chrono::{Datelike, NaiveDate, Utc};
use serde::Serialize;
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
/// executor 泛型：预留事务（ensure 阶段 1 / reject）内用事务连接计数（含本事务未提交行）。
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

/// 插入预占行（事务内调用）：title NULL、status=pending_review、regenerate_count 定值、
/// tokens 0——预占行计入非终结（并发 ensure 看到即跳过），LLM 填充在锁外进行。
async fn insert_reservation<'e, E>(
    exec: E,
    target_date: &str,
    difficulty: &str,
    category: &str,
    order_index: i64,
    regenerate_count: i64,
) -> Result<i64, AppError>
where
    E: sqlx::Executor<'e, Database = sqlx::Sqlite>,
{
    let now = Utc::now().timestamp_millis();
    let id = sqlx::query(
        "INSERT INTO article (target_date, difficulty, content_category, order_index, title, status, regenerate_count, prompt_tokens, completion_tokens, created_at, updated_at)
         VALUES (?, ?, ?, ?, NULL, 'pending_review', ?, 0, 0, ?, ?)",
    )
    .bind(target_date)
    .bind(difficulty)
    .bind(category)
    .bind(order_index)
    .bind(regenerate_count)
    .bind(now)
    .bind(now)
    .execute(exec)
    .await?
    .last_insert_rowid();
    Ok(id)
}

/// 幂等 + 并发安全（预占行模式，写锁不跨 LLM 调用）：
/// 阶段 1（BEGIN IMMEDIATE 短事务，毫秒级）：每难度统计非终结行（pending_review/approved），
/// 缺失槽位 INSERT 预占行（title NULL、regenerate_count=0）→ COMMIT。并发 ensure 的计数
/// 发生在先到者 COMMIT 后，看到预占行即跳过——幂等成立。sqlx 默认 begin() 是 DEFERRED
/// （先 SELECT 后 INSERT 的窗口内两会话同见 0），故用 begin_with 显式指定 IMMEDIATE。
/// 阶段 2（无锁）：逐行填充 pending_review AND title IS NULL 的预占行（LLM → UPDATE +
/// 段落 INSERT）；单篇失败标记 failed（title 仍 NULL）并继续处理其余行，下次 ensure 补新
/// 预占行替换——单篇失败不回滚整批、不浪费其余稿件。
///
/// 若把 LLM 调用放进持有写锁的事务（15 次真实调用每次可达 90s，整批分钟级），并发第二
/// ensure 在 sqlx 默认 5s busy_timeout 后报 SQLITE_BUSY，且批处理窗口内所有写入方
/// （T12 审核、查词 usage_log/cache）全被阻塞——故预留与填充必须分离。
pub async fn ensure_daily_generation(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    fetcher: &dyn SourceFetcher,
    target_date: &str,
) -> Result<(), AppError> {
    // 阶段 1：短事务预留缺失槽位（锁毫秒级；出错自动回滚，不落半成品）
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
            insert_reservation(&mut *tx, target_date, difficulty, category, order, 0).await?;
            need -= 1;
        }
    }
    tx.commit().await?;
    // 阶段 2：无锁填充预占行（LLM 调用不持写锁）
    let pending: Vec<i64> = sqlx::query_scalar(
        "SELECT id FROM article WHERE target_date = ? AND status = 'pending_review' AND title IS NULL ORDER BY id",
    )
    .bind(target_date)
    .fetch_all(pool)
    .await?;
    for id in pending {
        if let Err(e) = generate_one(pool, cfg, api, fetcher, id).await {
            // 单篇失败不阻断整批：行已标记 failed，下次 ensure 自动补预占行替换
            tracing::warn!("article {id} generation failed, will be re-reserved next run: {e:?}");
        }
    }
    Ok(())
}

/// 单篇生成（填充模式）：只处理预占行（status=pending_review AND title IS NULL）——
/// LLM 出稿 → UPDATE 该行（title/tokens 真值）+ INSERT 段落（`英文|||中文` 单列）；
/// 生成失败 → UPDATE status='failed'（title 仍 NULL），failed 不计入非终结。
/// 不再负责建行（预占行由 ensure 阶段 1 / reject 短事务创建）；已填充/已终结/不存在的行
/// 幂等跳过（并发下另一路已处理则不重复写入）。用量记账失败不阻断生成（成本统计尽力而为）。
pub async fn generate_one(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    fetcher: &dyn SourceFetcher,
    article_id: i64,
) -> Result<(), AppError> {
    let row: Option<(String, String, i64)> = sqlx::query_as(
        "SELECT difficulty, content_category, order_index FROM article WHERE id = ? AND status = 'pending_review' AND title IS NULL",
    )
    .bind(article_id)
    .fetch_optional(pool)
    .await?;
    let (difficulty, category, order_index) = match row {
        Some(r) => r,
        None => return Ok(()), // 已填充/已终结/不存在：幂等跳过（并发下另一路已处理）
    };
    // NEWS 选源：池空自动抓取；抓取失败/池空降级 None（自由发挥，不阻断生成）
    let source = if category == "NEWS" {
        source_service::pick_source(pool, cfg, fetcher).await?
    } else {
        None
    };
    let started = tokio::time::Instant::now();
    let generated = llm_service::generate_article_content(
        pool,
        api,
        cfg,
        &difficulty,
        &category,
        order_index,
        source.as_ref(),
    )
    .await;
    let latency = started.elapsed().as_millis() as i64;
    let (title, paragraphs, prompt_tokens, completion_tokens) = match generated {
        Ok(r) => r,
        Err(e) => {
            // 生成失败：标记 failed（title 仍 NULL），下次 ensure 补预占行替换
            sqlx::query(
                "UPDATE article SET status = 'failed', updated_at = ? WHERE id = ? AND status = 'pending_review' AND title IS NULL",
            )
            .bind(Utc::now().timestamp_millis())
            .bind(article_id)
            .execute(pool)
            .await?;
            return Err(e);
        }
    };
    // 成功：填 title/tokens + 段落——包进短事务（毫秒级、无 LLM 调用，不违反预占行原则）。
    // 段落 INSERT 失败整体回滚 → title 仍 NULL → 下次 ensure 重填；不留「title 非空 +
    // 0~k 段」的半写态（F1：无自愈路径的永久悬挂）。条件 UPDATE 防并发双填——
    // 另一路已填充则本路 affected=0，跳过段落写入幂等返回。
    let mut tx = pool.begin().await?;
    let n = sqlx::query(
        "UPDATE article SET title = ?, source_article_id = ?, prompt_tokens = ?, completion_tokens = ?, updated_at = ?
         WHERE id = ? AND status = 'pending_review' AND title IS NULL",
    )
    .bind(&title)
    .bind(source.as_ref().map(|s| s.id))
    .bind(prompt_tokens as i64)
    .bind(completion_tokens as i64)
    .bind(Utc::now().timestamp_millis())
    .bind(article_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if n == 0 {
        tx.commit().await?;
        return Ok(());
    }
    let mut o = 0i64;
    for (_, en, zh) in &paragraphs {
        o += 1;
        sqlx::query(
            "INSERT INTO article_paragraph (article_id, order_index, text) VALUES (?, ?, ?)",
        )
        .bind(article_id)
        .bind(o)
        .bind(format!("{en}|||{zh}"))
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    // 段落文本格式：`英文|||中文`（下发时拆分；服务端不存第二列避免 1NF 争议）
    llm_service::record_usage(
        pool,
        None,
        "article_generate",
        prompt_tokens,
        completion_tokens,
        latency,
    )
    .await
    .ok();
    Ok(())
}

/// 审核通过：仅已生成的 pending_review（title 非空）可 approve——预占/生成中行（title NULL）
/// 不可过审（F2：否则 approved + title NULL → T10 下发空标题）。其余（含重复）→ NotFound。
pub async fn approve_article(pool: &SqlitePool, id: i64) -> Result<(), AppError> {
    let now = Utc::now().timestamp_millis();
    let n = sqlx::query(
        "UPDATE article SET status = 'approved', updated_at = ? WHERE id = ? AND status = 'pending_review' AND title IS NOT NULL",
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

/// 审核拒绝：旧行 → rejected（达补生上限则 rejected_final）；未达上限时同一短事务内
/// INSERT 补生成预占行（regenerate_count = 父行 regen+1、title NULL）→ 事务外填充——
/// regenerate_count 预留时定值（无需 MAX(id) 回写，无并发错行风险）。预算在预留时校验
/// （预占行即消耗每日文章配额）。守卫与 approve 对称（审查加固）：仅已生成行
/// （title IS NOT NULL）可拒绝——预占/生成中行管理员看不到内容，误拒只会浪费一次
/// 补生成，直接 NotFound。
///
/// 补生成失败降级决策（T12 审查）：拒绝语义（旧行 rejected + 补生成预占行已提交）在
/// 事务内即已完成，填充失败不再上抛——否则客户端收到 500/502/504 但拒绝已生效，重试
/// 撞 404，新行落 failed 也无端点可处置。记 warn 后返回成功；新行保持 failed
/// （title 仍 NULL），由下次 ensure 自动补预占行替换（预占行自愈，不浪费槽位）。
pub async fn reject_article(
    pool: &SqlitePool,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    fetcher: &dyn SourceFetcher,
    id: i64,
    reason: &str,
) -> Result<(), AppError> {
    let row: Option<(String, String, i64, i64)> = sqlx::query_as(
        "SELECT target_date, difficulty, order_index, regenerate_count FROM article WHERE id = ? AND status = 'pending_review' AND title IS NOT NULL",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    let (date, difficulty, order, regen) =
        row.ok_or(AppError::NotFound("article not pending_review".into()))?;
    let now = Utc::now().timestamp_millis();
    let mut tx = pool.begin_with("BEGIN IMMEDIATE").await?;
    // F3 守卫：并发双 reject 同一行时，后到者的 UPDATE 条件（仍为 pending_review）不命中
    // （affected=0）→ 不建补生成行，返回 NotFound——避免双插预占行。
    // title IS NOT NULL 同步进 UPDATE：并发 ensure 在 SELECT 后填充该行（title 置真）时
    // 本路同样不命中——SELECT/UPDATE 守卫一致（与 approve 的 title 守卫对称）。
    let n = sqlx::query(
        "UPDATE article SET status = 'rejected', reject_reason = ?, updated_at = ? WHERE id = ? AND status = 'pending_review' AND title IS NOT NULL",
    )
    .bind(reason)
    .bind(now)
    .bind(id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if n == 0 {
        // 另一路已先行处理（或行已非 pending）：本路不建任何行（tx 丢弃即回滚）
        return Err(AppError::NotFound("article not pending_review".into()));
    }
    if regen >= REGENERATE_CAP {
        sqlx::query("UPDATE article SET status = 'rejected_final', updated_at = ? WHERE id = ?")
            .bind(now)
            .bind(id)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        return Ok(());
    }
    // 预算内预留补生成槽位（短事务持锁，LLM 填充在事务外）
    check_daily_budget(&mut *tx, cfg).await?;
    let category = category_for(&difficulty, &date, order + regen + 1);
    let new_id =
        insert_reservation(&mut *tx, &date, &difficulty, category, order, regen + 1).await?;
    tx.commit().await?;
    // 事务外填充：失败 → 新行 failed（title NULL），下次 ensure 补预占行替换——
    // 按降级决策记 warn 返回成功（拒绝语义已完成，错误不上抛）。
    if let Err(e) = generate_one(pool, cfg, api, fetcher, new_id).await {
        tracing::warn!(
            "article {id} replacement generation failed, reservation {new_id} will be re-reserved by next ensure: {e:?}"
        );
    }
    Ok(())
}

/// 审核期编辑文章内容（仅已生成 pending_review：status + title IS NOT NULL 双守卫，与
/// approve/reject/填充对称——预占/生成中行（title NULL）归生成管线所有，PUT 直接 404；
/// 否则管理员内容写进预占行会被后续 generate_one 填充（守卫 AND title IS NULL）affected=0
/// 静默跳过，LLM 出稿白耗预算被丢弃）。title 非空；paragraphs ≥1；每段 en/zh 至少一个非空
/// （否则落库 `|||` 读回两条空串）。
/// 事务内：UPDATE title → DELETE 旧段落 → INSERT 新段落（`英文|||中文` 单列，与生成一致）。
/// order_index 由服务端按请求序重编 1..n（忽略客户端值——生成路径同规，客户端序号不可信）。
/// 并发编辑：UPDATE 以 status+title 条件为守卫，后到者 affected=0 → NotFound；校验失败零写入。
pub async fn update_article_content(
    pool: &SqlitePool,
    id: i64,
    title: &str,
    paragraphs: &[(i64, String, String)],
) -> Result<(), AppError> {
    if title.trim().is_empty() {
        return Err(AppError::BadRequest("BAD_PARAM".into(), "title required".into()));
    }
    if paragraphs.is_empty() {
        return Err(AppError::BadRequest(
            "BAD_PARAM".into(),
            "paragraphs required".into(),
        ));
    }
    if paragraphs
        .iter()
        .any(|(_, en, zh)| en.trim().is_empty() && zh.trim().is_empty())
    {
        return Err(AppError::BadRequest(
            "BAD_PARAM".into(),
            "paragraph text required".into(),
        ));
    }
    let mut tx = pool.begin().await?;
    let n = sqlx::query(
        "UPDATE article SET title = ?, updated_at = ? WHERE id = ? AND status = 'pending_review' AND title IS NOT NULL",
    )
    .bind(title.trim())
    .bind(Utc::now().timestamp_millis())
    .bind(id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound("article not pending_review".into()));
    }
    sqlx::query("DELETE FROM article_paragraph WHERE article_id = ?")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for (i, (_, en, zh)) in paragraphs.iter().enumerate() {
        sqlx::query("INSERT INTO article_paragraph (article_id, order_index, text) VALUES (?, ?, ?)")
            .bind(id)
            .bind((i + 1) as i64)
            .bind(format!("{en}|||{zh}"))
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}

/// 下发/管理视图：段落已拆分（英文、中文），供 T10 下发与 T12 审核列表复用。
/// title 语义：NULL title（预占/生成中/失败行）映射为空串 ""——空 title = 预占/生成中/失败；
/// T10 只下发 approved（title 必非空），不受影响。
/// Serialize：T12 管理端点经 `serde_json::to_value` 直出（段落序列化为
/// `[[order, 英文, 中文], ...]` 数组形态）；T10 下发仍走 ArticleJson 嵌套对象，互不影响。
#[derive(Serialize)]
pub struct ArticleView {
    pub id: i64,
    pub target_date: String,
    pub difficulty: String,
    pub content_category: String,
    pub order_index: i64,
    pub title: String,
    pub status: String,
    pub regenerate_count: i64,
    pub source_url: Option<String>,
    pub paragraphs: Vec<(i64, String, String)>,
}

/// load_view 的视图字段（元组打包，规避 too_many_arguments / type_complexity）：
/// (id, title, target_date, difficulty, content_category, order_index, status, regenerate_count, source_url)
type ViewFields = (
    i64,
    Option<String>,
    String,
    String,
    String,
    i64,
    String,
    i64,
    Option<String>,
);

async fn load_view(pool: &SqlitePool, f: ViewFields) -> Result<ArticleView, AppError> {
    let (id, title, date, difficulty, category, order, status, regen, source_url) = f;
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
        title: title.unwrap_or_default(),
        status,
        regenerate_count: regen,
        source_url,
        paragraphs,
    })
}

pub async fn get_article(pool: &SqlitePool, id: i64) -> Result<ArticleView, AppError> {
    // 行数据元组别名（规避 type_complexity）
    type ArticleRow = (
        Option<String>,
        String,
        String,
        String,
        i64,
        String,
        i64,
        Option<String>,
    );
    let row: Option<ArticleRow> = sqlx::query_as(
        "SELECT a.title, a.target_date, a.difficulty, a.content_category, a.order_index, a.status, a.regenerate_count, s.source_url
         FROM article a LEFT JOIN article_source s ON s.id = a.source_article_id WHERE a.id = ?",
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    match row {
        Some((title, date, diff, cat, order, status, regen, source_url)) => {
            load_view(pool, (id, title, date, diff, cat, order, status, regen, source_url)).await
        }
        None => Err(AppError::NotFound("article not found".into())),
    }
}

/// 按日下发：仅 approved 可见，按难度、order_index 排序。
pub async fn get_approved_by_date(
    pool: &SqlitePool,
    date: &str,
) -> Result<Vec<ArticleView>, AppError> {
    let rows: Vec<(i64, Option<String>, String, String, i64, i64, Option<String>)> = sqlx::query_as(
        "SELECT a.id, a.title, a.difficulty, a.content_category, a.order_index, a.regenerate_count, s.source_url
         FROM article a LEFT JOIN article_source s ON s.id = a.source_article_id
         WHERE a.target_date = ? AND a.status = 'approved' ORDER BY a.difficulty, a.order_index",
    )
    .bind(date)
    .fetch_all(pool)
    .await?;
    let mut out = Vec::new();
    for (id, title, diff, cat, order, regen, source_url) in rows {
        out.push(
            load_view(
                pool,
                (
                    id,
                    title,
                    date.to_string(),
                    diff,
                    cat,
                    order,
                    "approved".into(),
                    regen,
                    source_url,
                ),
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
        "SELECT a.id, a.title, a.target_date, a.difficulty, a.content_category, a.order_index, a.status, a.regenerate_count, s.source_url
         FROM article a LEFT JOIN article_source s ON s.id = a.source_article_id",
    );
    let mut conds: Vec<&str> = Vec::new();
    let mut args: Vec<String> = Vec::new();
    if let Some(d) = date {
        conds.push("a.target_date = ?");
        args.push(d.to_string());
    }
    if let Some(s) = status {
        conds.push("a.status = ?");
        args.push(s.to_string());
    }
    if !conds.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&conds.join(" AND "));
    }
    sql.push_str(" ORDER BY a.target_date DESC, a.difficulty, a.order_index");
    let mut q = sqlx::query_as::<
        _,
        (
            i64,
            Option<String>,
            String,
            String,
            String,
            i64,
            String,
            i64,
            Option<String>,
        ),
    >(sqlx::AssertSqlSafe(sql));
    for a in &args {
        q = q.bind(a);
    }
    let rows = q.fetch_all(pool).await?;
    let mut out = Vec::new();
    for (id, title, date, diff, cat, order, status, regen, source_url) in rows {
        out.push(
            load_view(pool, (id, title, date, diff, cat, order, status, regen, source_url)).await?,
        );
    }
    Ok(out)
}
