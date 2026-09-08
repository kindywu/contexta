// src/services/admin_articles.ts
// 管理端文章读取与编辑（文章视角列表/详情/历史 + 审核期内容编辑）。
// 响应键名精确 snake_case（管理端契约）；段落 order_index 响应侧 1 起——
// 存储层 article_paragraphs.paragraph_index 与引擎一致为 0 基（article_reader 同规派生 +1）。
import type { Database } from "bun:sqlite"; // 连接由调用方开（routers/admin），本模块只用类型
import { badRequest, notFound } from "../response";

/** review 行（wire）：详情与列表行共用。 */
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

/** 文章列表行（文章视角）：articles 白名单列 + review 行 + 所属槽位 + 现指向标记。 */
export interface ArticleListRow {
  id: number;
  run_date: string;
  difficulty: string;
  category: string;
  title_en: string;
  title_zh: string;
  source_url: string | null;
  paragraph_count: number;
  created_at: string;
  slot_id: number | null;
  slot_index: number | null;
  /** 文章是否为所属槽位当前指向（补生成替换后旧文为 false，不可再审核）。 */
  is_current: boolean;
  review: ReviewWire | null;
}

/** 列表查询参数（HTTP 层已校验白名单/取值；service 信任输入）。 */
export interface ArticleListQuery {
  startDate: string;
  endDate: string;
  /** 'pending_review' | 'approved' | 'rejected'（rejected 含 rejected_final）；缺省全部。 */
  status?: string;
  page: number; // 1 起
  pageSize: number; // 15 | 30 | 45
  sortBy: string; // ARTICLE_SORTABLE 之一
  sortDir: "asc" | "desc";
}

/** 可排序列（服务端白名单：列名不能参数化，非法输入在 HTTP 层 400，此处兜底默认）。 */
export const ARTICLE_SORTABLE = [
  "run_date",
  "slot_index",
  "created_at",
  "difficulty",
  "category",
  "status",
  "paragraph_count",
  "id",
] as const;

/** 时间段内（不含 status 筛选）审核状态分布——列表摘要。 */
export interface ArticleListStats {
  total: number;
  pending_review: number;
  approved: number;
  /** rejected + rejected_final 合计。 */
  rejected: number;
  /** 异常槽位数：非 success（error/rejected，均无文章行，articles 视角不可见——摘要"异常"入口）。 */
  error_slots: number;
}

export interface ArticleListResult {
  items: ArticleListRow[];
  total: number;
  stats: ArticleListStats;
}

/** 排序列 → SQL 片段（白名单映射后拼接，无注入面；status 记 review 行状态）。 */
const SORT_COLUMN_SQL: Record<string, string> = {
  run_date: "a.run_date",
  slot_index: "s.slot_index",
  created_at: "a.created_at",
  difficulty: "a.difficulty",
  category: "a.category",
  status: "r.status",
  paragraph_count: "a.paragraph_count",
  id: "a.id",
};

/** 状态过滤 → SQL 条件片段：'rejected' 聚合 rejected 与 rejected_final（终拒同属拒绝）。 */
const STATUS_SQL: Record<string, string> = {
  pending_review: "r.status = 'pending_review'",
  approved: "r.status = 'approved'",
  rejected: "r.status IN ('rejected', 'rejected_final')",
};

function toReviewWire(row: Record<string, unknown>): ReviewWire {
  return {
    id: row.id as number,
    status: row.status as string,
    reject_reason: (row.reject_reason as string | null) ?? null,
    reviewed_by: (row.reviewed_by as string | null) ?? null,
    reviewed_at: (row.reviewed_at as string | null) ?? null,
  };
}

/**
 * 同槽全部 review 行倒序（id DESC，新 → 旧）；槽位以文章的 review 行 slot_id 为准
 * （与详情槽位归属同规）。无 review 行返回 []。
 */
function reviewHistoryForArticleSlot(db: Database, articleId: number): ReviewHistoryWire[] {
  const slot = db
    .query("SELECT slot_id FROM article_review WHERE article_id = ?")
    .get(articleId) as { slot_id: number } | undefined;
  if (!slot) return [];
  const rows = db
    .query(
      `SELECT article_id, status, reject_reason, reviewed_by, reviewed_at
       FROM article_review WHERE slot_id = ? ORDER BY id DESC`,
    )
    .all(slot.slot_id) as Record<string, unknown>[];
  return rows.map((h) => ({
    article_id: h.article_id as number,
    status: h.status as string,
    reject_reason: (h.reject_reason as string | null) ?? null,
    reviewed_by: (h.reviewed_by as string | null) ?? null,
    reviewed_at: (h.reviewed_at as string | null) ?? null,
  }));
}

/**
 * 文章视角分页列表（时间段 run_date 过滤 + 可选状态过滤 + 白名单排序 + 统计）。
 * 行 = articles 一行；review = 该文章审核行（每篇 success 文章必有，异常缺口 LEFT JOIN 兜 null）；
 * slot 归属 = review.slot_id（历史文归属创建它的槽位，与 getArticleDetail 同规）；
 * is_current = 任何槽位现指向（补生成后旧文 false）。
 * 统计口径 = 时间段内全量（不含 status 筛选），与分页无关。
 */
export function listArticles(db: Database, q: ArticleListQuery): ArticleListResult {
  const where = [`a.run_date BETWEEN ? AND ?`];
  const params: (string | number)[] = [q.startDate, q.endDate];
  if (q.status) {
    const cond = STATUS_SQL[q.status];
    if (!cond) throw badRequest("invalid status");
    where.push(cond);
  }
  const whereSql = where.join(" AND ");

  const items = db
    .query(
      `SELECT a.id, a.run_date, a.difficulty, a.category, a.title_en, a.title_zh,
              a.source_url, a.paragraph_count, a.created_at,
              r.id AS review_id, r.status AS review_status, r.reject_reason,
              r.reviewed_by, r.reviewed_at,
              s.id AS slot_id, s.slot_index,
              EXISTS(SELECT 1 FROM batch_slots c WHERE c.article_id = a.id) AS is_current
       FROM articles a
       LEFT JOIN article_review r ON r.article_id = a.id
       LEFT JOIN batch_slots s ON s.id = r.slot_id
       WHERE ${whereSql}
       ORDER BY ${SORT_COLUMN_SQL[q.sortBy] ?? "a.run_date"} ${q.sortDir === "asc" ? "ASC" : "DESC"},
                s.slot_index ASC,
                a.id ${q.sortDir === "asc" ? "ASC" : "DESC"}
       LIMIT ? OFFSET ?`,
    )
    .all(...params, q.pageSize, (q.page - 1) * q.pageSize) as Record<string, unknown>[];

  const countRow = db
    .query(
      `SELECT COUNT(*) AS c FROM articles a
       LEFT JOIN article_review r ON r.article_id = a.id WHERE ${whereSql}`,
    )
    .get(...params) as { c: number };

  // 异常槽位计数：非 success 槽位（error + rejected，均无文章行——articles 视角不可见；
  // 摘要 tag“异常槽位”据此显示并与 GET /api/admin/slots 口径一致）
  const errorSlots = db
    .query(`SELECT COUNT(*) AS n FROM batch_slots WHERE run_date BETWEEN ? AND ? AND status != 'success'`)
    .get(q.startDate, q.endDate) as { n: number };

  const statsRow = db
    .query(
      `SELECT COUNT(*) AS total,
              SUM(CASE WHEN r.status = 'pending_review' THEN 1 ELSE 0 END) AS pending_review,
              SUM(CASE WHEN r.status = 'approved' THEN 1 ELSE 0 END) AS approved,
              SUM(CASE WHEN r.status IN ('rejected', 'rejected_final') THEN 1 ELSE 0 END) AS rejected
       FROM articles a
       LEFT JOIN article_review r ON r.article_id = a.id
       WHERE a.run_date BETWEEN ? AND ?`,
    )
    .get(q.startDate, q.endDate) as {
    total: number;
    pending_review: number | null;
    approved: number | null;
    rejected: number | null;
    error_slots: number;
  };

  return {
    items: items.map((row) => ({
      id: row.id as number,
      run_date: row.run_date as string,
      difficulty: row.difficulty as string,
      category: row.category as string,
      title_en: row.title_en as string,
      title_zh: row.title_zh as string,
      source_url: (row.source_url as string | null) ?? null,
      paragraph_count: row.paragraph_count as number,
      created_at: row.created_at as string,
      slot_id: (row.slot_id as number | null) ?? null,
      slot_index: (row.slot_index as number | null) ?? null,
      is_current: (row.is_current as number) === 1,
      review:
        row.review_id == null
          ? null
          : {
              id: row.review_id as number,
              status: row.review_status as string,
              reject_reason: (row.reject_reason as string | null) ?? null,
              reviewed_by: (row.reviewed_by as string | null) ?? null,
              reviewed_at: (row.reviewed_at as string | null) ?? null,
            },
    })),
    total: countRow.c,
    stats: {
      total: statsRow.total,
      pending_review: statsRow.pending_review ?? 0,
      approved: statsRow.approved ?? 0,
      rejected: statsRow.rejected ?? 0,
      error_slots: errorSlots.n,
    },
  };
}

/** ArticleDetailWire 契约含 history（同槽审核历史，列表视角下详情页的时间线数据源）。 */
export interface ArticleDetailWire {
  /** articles 全行（snake_case，含 batch_id/markdown_path/created_at 等）。 */
  [k: string]: unknown;
  paragraphs: { order_index: number; english_text: string; chinese_translation: string }[];
  review: ReviewWire | null;
  history: ReviewHistoryWire[];
  slot_id: number | null;
  slot_index: number | null;
  run_date: string;
}

/**
 * 文章详情（管理端）：articles 全行 + 段落（order_index 1 起）+ review 行 + 所属槽位
 * + 同槽审核历史（倒序）。槽位以 review.slot_id 为准（旧文被补生成换指后仍归属其槽位）；
 * 无 review 行时回退 batch_slots.article_id（理论不会出现，兜底）。不存在 → 404。
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
  const reviewRow = db
    .query(
      "SELECT id, status, reject_reason, reviewed_by, reviewed_at, slot_id FROM article_review WHERE article_id = ?",
    )
    .get(articleId) as (Record<string, unknown> & { slot_id: number }) | undefined;
  const review = reviewRow ? toReviewWire(reviewRow) : null;
  const slot = reviewRow
    ? (db
        .query("SELECT id, slot_index FROM batch_slots WHERE id = ?")
        .get(reviewRow.slot_id) as { id: number; slot_index: number } | undefined)
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
    history: reviewRow ? reviewHistoryForArticleSlot(db, articleId) : [],
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
