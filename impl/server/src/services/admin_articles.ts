// src/services/admin_articles.ts
// 管理端文章读取与编辑（槽位审核视图/详情/历史 + 审核期内容编辑）。
// 响应键名精确 snake_case（管理端契约）；段落 order_index 响应侧 1 起——
// 存储层 article_paragraphs.paragraph_index 与引擎一致为 0 基（article_reader 同规派生 +1）。
import type { Database } from "bun:sqlite"; // 连接由调用方开（routers/admin），本模块只用类型
import { badRequest, notFound } from "../response";

/** 槽位视图的当前文章（白名单列，source_url 可空）。 */
export interface SlotArticleWire {
  id: number;
  category: string;
  title_en: string;
  title_zh: string;
  source_url: string | null;
  paragraph_count: number;
  path: string;
  run_date: string;
}

/** review 行（wire）：详情与槽位视图共用。 */
export interface ReviewWire {
  id: number;
  status: string;
  reject_reason: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
}

/** history 行：同槽全部 review 行（含当前文章行）倒序，关联 article_id（契约不含 id）。 */
export interface ReviewHistoryWire {
  article_id: number;
  status: string;
  reject_reason: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
}

export interface SlotView {
  slot_id: number;
  slot_index: number;
  difficulty: string;
  status: string;
  attempts: number;
  thread_id: string;
  article: SlotArticleWire | null;
  review: ReviewWire | null;
  history: ReviewHistoryWire[];
}

export interface ArticleDetailWire {
  /** articles 全行（snake_case，含 batch_id/markdown_path/created_at 等）。 */
  [k: string]: unknown;
  paragraphs: { order_index: number; english_text: string; chinese_translation: string }[];
  review: ReviewWire | null;
  slot_id: number | null;
  slot_index: number | null;
  run_date: string;
}

/** 按 id 查文章白名单列（槽位视图用）；不存在返回 null。 */
function slotArticle(db: Database, articleId: number): SlotArticleWire | null {
  const row = db
    .query(
      `SELECT id, category, title_en, title_zh, source_url, paragraph_count, path, run_date
       FROM articles WHERE id = ?`,
    )
    .get(articleId) as Record<string, unknown> | undefined;
  if (!row) return null;
  return {
    id: row.id as number,
    category: row.category as string,
    title_en: row.title_en as string,
    title_zh: row.title_zh as string,
    source_url: (row.source_url as string | null) ?? null,
    paragraph_count: row.paragraph_count as number,
    path: row.path as string,
    run_date: row.run_date as string,
  };
}

/** 某文章的 review 行；无行返回 null。 */
function reviewOf(db: Database, articleId: number): ReviewWire | null {
  const row = db
    .query(
      "SELECT id, status, reject_reason, reviewed_by, reviewed_at FROM article_review WHERE article_id = ?",
    )
    .get(articleId) as Record<string, unknown> | undefined;
  if (!row) return null;
  return {
    id: row.id as number,
    status: row.status as string,
    reject_reason: (row.reject_reason as string | null) ?? null,
    reviewed_by: (row.reviewed_by as string | null) ?? null,
    reviewed_at: (row.reviewed_at as string | null) ?? null,
  };
}

/**
 * 槽位审核视图（某日全部槽位，slot_index 升序）：
 * - article = 槽位当前指向文章（白名单列）；review = 该文章的最新审核行（槽位当前文章的）；
 * - history = 该槽位全部 review 行（含当前行）倒序（id DESC，新 → 旧）；
 * - status 过滤：匹配 review.status；无 review 行的槽位（error/rejected 无文章）
 *   仅当 status 为空或等于其 slot.status 时出现。
 * 任意字符串 date 均安全（参数化查询），无匹配行即空数组。
 */
export function listSlotsByDate(db: Database, date: string, status?: string): SlotView[] {
  const slotRows = db
    .query("SELECT * FROM batch_slots WHERE run_date = ? ORDER BY slot_index ASC")
    .all(date) as Record<string, unknown>[];
  const out: SlotView[] = [];
  for (const s of slotRows) {
    const slotId = s.id as number;
    const articleId = s.article_id as number | null;
    const article = articleId != null ? slotArticle(db, articleId) : null;
    const review = articleId != null ? reviewOf(db, articleId) : null;
    if (status && (review ? review.status !== status : s.status !== status)) continue;
    const history = db
      .query(
        `SELECT article_id, status, reject_reason, reviewed_by, reviewed_at
         FROM article_review WHERE slot_id = ? ORDER BY id DESC`,
      )
      .all(slotId) as Record<string, unknown>[];
    out.push({
      slot_id: slotId,
      slot_index: s.slot_index as number,
      difficulty: s.difficulty as string,
      status: s.status as string,
      attempts: s.attempts as number,
      thread_id: s.thread_id as string,
      article,
      review,
      history: history.map((h) => ({
        article_id: h.article_id as number,
        status: h.status as string,
        reject_reason: (h.reject_reason as string | null) ?? null,
        reviewed_by: (h.reviewed_by as string | null) ?? null,
        reviewed_at: (h.reviewed_at as string | null) ?? null,
      })),
    });
  }
  return out;
}

/**
 * 文章详情（管理端）：articles 全行 + 段落（order_index 1 起）+ review 行 + 所属槽位。
 * 槽位以 review.slot_id 为准（旧文被补生成换指后仍归属其槽位）；无 review 行时
 * 回退 batch_slots.article_id（理论不会出现，兜底）。不存在 → 404。
 */
export function getArticleDetail(db: Database, articleId: number): ArticleDetailWire {
  const row = db.query("SELECT * FROM articles WHERE id = ?").get(articleId) as
    | Record<string, unknown>
    | undefined;
  if (!row) throw notFound("article not found");
  const paragraphs = db
    .query(
      "SELECT paragraph_index, text_en, text_zh FROM article_paragraphs WHERE article_id = ? ORDER BY paragraph_index",
    )
    .all(articleId) as { paragraph_index: number; text_en: string; text_zh: string }[];
  const review = reviewOf(db, articleId);
  const slot = review
    ? (db
        .query("SELECT id, slot_index FROM batch_slots WHERE id = (SELECT slot_id FROM article_review WHERE article_id = ?)")
        .get(articleId) as { id: number; slot_index: number } | undefined)
    : (db.query("SELECT id, slot_index FROM batch_slots WHERE article_id = ?").get(articleId) as
        | { id: number; slot_index: number }
        | undefined);
  return {
    ...row,
    source_url: (row.source_url as string | null) ?? null,
    paragraphs: paragraphs.map((p) => ({
      order_index: p.paragraph_index + 1,
      english_text: p.text_en,
      chinese_translation: p.text_zh,
    })),
    review,
    slot_id: slot?.id ?? null,
    slot_index: slot?.slot_index ?? null,
    run_date: row.run_date as string,
  };
}

/** 编辑请求的段落条目（wire：english_text/chinese_translation；客户端序号不可信，按请求序重编）。 */
export interface ParagraphEditWire {
  english_text?: unknown;
  chinese_translation?: unknown;
}

/**
 * 审核期编辑文章内容（替换 title_en 与全部段落，title_zh 不动）。
 * 守卫（不满足 → 404）：有 review 行、status = pending_review、文章是槽位现指向
 * （旧文不可编辑——审批状态机由槽位现指向驱动）。
 * 校验（不满足 → 400）：title 非空；paragraphs ≥ 1；每段 en/zh 至少一个非空。
 * 单事务：UPDATE title_en（+ paragraph_count 同步）→ DELETE 旧段落 → 按请求序插入
 * （paragraph_index = 0 基，与引擎生成路径一致；响应侧 order_index 派生 +1）。
 */
export function updateArticleContent(
  db: Database,
  articleId: number,
  title: unknown,
  paragraphs: unknown,
): void {
  if (typeof title !== "string" || title.trim() === "") {
    throw badRequest("title required");
  }
  if (!Array.isArray(paragraphs) || paragraphs.length === 0) {
    throw badRequest("paragraphs required");
  }
  const items = paragraphs.map((p) => {
    const o = (typeof p === "object" && p !== null ? p : {}) as Record<string, unknown>;
    const en = typeof o.english_text === "string" ? o.english_text : "";
    const zh = typeof o.chinese_translation === "string" ? o.chinese_translation : "";
    if (en.trim() === "" && zh.trim() === "") {
      throw badRequest("paragraph text required");
    }
    return { en, zh };
  });
  const review = db
    .query("SELECT slot_id, status FROM article_review WHERE article_id = ?")
    .get(articleId) as { slot_id: number; status: string } | undefined;
  if (!review || review.status !== "pending_review") throw notFound("article not editable");
  const slot = db.query("SELECT article_id FROM batch_slots WHERE id = ?").get(review.slot_id) as
    | { article_id: number | null }
    | undefined;
  if (!slot || slot.article_id !== articleId) throw notFound("article not editable");

  db.transaction(() => {
    db.query("UPDATE articles SET title_en = ?, paragraph_count = ? WHERE id = ?").run(
      title,
      items.length,
      articleId,
    );
    db.query("DELETE FROM article_paragraphs WHERE article_id = ?").run(articleId);
    const stmt = db.query(
      "INSERT INTO article_paragraphs (article_id, paragraph_index, text_en, text_zh) VALUES (?, ?, ?, ?)",
    );
    items.forEach((p, i) => stmt.run(articleId, i, p.en, p.zh));
  })();
}
