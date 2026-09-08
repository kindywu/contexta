import type { Database } from "bun:sqlite"; // 连接由调用方开（daily/retry），db.ts 只用类型
import type { GeneratedArticle } from "./graph/state";
import type { Category, Difficulty } from "./schema";

/** 槽位状态：pending=未完成（含意外中断）；error/rejected=跑完但失败；success=完成。 */
export type SlotStatus = "pending" | "success" | "rejected" | "error";

export interface BatchRow {
  id: number;
  runDate: string;
  totalSlots: number;
  completedSlots: number;
  failedSlots: number;
  status: string;
}

export interface SlotRow {
  id: number;
  batchId: number;
  runDate: string;
  slotIndex: number;
  difficulty: Difficulty;
  threadId: string;
  status: SlotStatus;
  attempts: number;
  articleId: number | null;
  /** 失败/拒绝原因（未持久化的旧数据/无原因时为 null；nullable 列）。 */
  errorMessage: string | null;
}

/**
 * 幂等建表：CREATE TABLE IF NOT EXISTS（含新列）+ 旧库补列。
 * 参考 docs/database-schema.md 的现有 DDL（run_log 已于 2026-08-29 移除，不再建表）。
 */
export function ensureSchema(db: Database): void {
  db.run(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS article_batches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_date TEXT NOT NULL UNIQUE,
      total_slots INTEGER NOT NULL,
      completed_slots INTEGER NOT NULL DEFAULT 0,
      failed_slots INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'running'
        CHECK (status IN ('running', 'completed', 'completed_with_failures', 'failed')),
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      finished_at TEXT
    );
    CREATE TABLE IF NOT EXISTS articles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL REFERENCES article_batches(id),
      run_date TEXT NOT NULL,
      difficulty TEXT NOT NULL,
      category TEXT NOT NULL,
      path TEXT NOT NULL CHECK (path IN ('A', 'B')),
      source_url TEXT,
      title_en TEXT NOT NULL,
      title_zh TEXT NOT NULL,
      paragraph_count INTEGER NOT NULL,
      markdown_path TEXT NOT NULL,
      thread_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS article_paragraphs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      article_id INTEGER NOT NULL REFERENCES articles(id),
      paragraph_index INTEGER NOT NULL,
      text_en TEXT NOT NULL,
      text_zh TEXT NOT NULL,
      UNIQUE(article_id, paragraph_index)
    );
    CREATE TABLE IF NOT EXISTS batch_slots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL REFERENCES article_batches(id),
      run_date TEXT NOT NULL,
      slot_index INTEGER NOT NULL,
      difficulty TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','success','rejected','error')),
      attempts INTEGER NOT NULL DEFAULT 1,
      article_id INTEGER REFERENCES articles(id),
      error_message TEXT,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(batch_id, slot_index)
    );
    CREATE INDEX IF NOT EXISTS idx_articles_source_url ON articles(source_url);
    CREATE INDEX IF NOT EXISTS idx_articles_created_at ON articles(created_at);
    CREATE INDEX IF NOT EXISTS idx_articles_batch_id ON articles(batch_id);
    CREATE INDEX IF NOT EXISTS idx_batch_slots_run_date ON batch_slots(run_date);
  `);
  // 旧库补列（幂等建表不覆盖已存在的表）：
  // - articles.thread_id（索引阶段旧库无该列；新库 CREATE 已含，幂等跳过）
  // - batch_slots.error_message（失败/拒绝槽位的真实原因，供管理端与每日报告复用；
  //   此前未持久化，详见运行日志）
  const articleCols = db.query(`PRAGMA table_info(articles)`).all() as { name: string }[];
  if (!articleCols.some((c) => c.name === "thread_id")) {
    db.run(`ALTER TABLE articles ADD COLUMN thread_id TEXT`);
  }
  const slotCols = db.query(`PRAGMA table_info(batch_slots)`).all() as { name: string }[];
  if (!slotCols.some((c) => c.name === "error_message")) {
    db.run(`ALTER TABLE batch_slots ADD COLUMN error_message TEXT`);
  }
}

function toBatchRow(row: Record<string, unknown>): BatchRow {
  return {
    id: row.id as number,
    runDate: row.run_date as string,
    totalSlots: row.total_slots as number,
    completedSlots: row.completed_slots as number,
    failedSlots: row.failed_slots as number,
    status: row.status as string,
  };
}

export function getBatch(db: Database, runDate: string): BatchRow | undefined {
  const row = db
    .query("SELECT * FROM article_batches WHERE run_date = ?")
    .get(runDate) as Record<string, unknown> | undefined;
  return row ? toBatchRow(row) : undefined;
}

/**
 * 某日批次是否已收口（存在且 status != 'running'）：每日窗口触发时的"已生成成功"
 * 判定——收口（completed / completed_with_failures / failed）＝当天生成流程已结束，
 * 跳过不再触碰；无批次或 running（含中断未收口）＝未完成，交由 runFill 继续。
 */
export function isDailyBatchFinished(db: Database, runDate: string): boolean {
  const batch = getBatch(db, runDate);
  return batch !== undefined && batch.status !== "running";
}

/**
 * 新建批次 + 插入槽位行，单事务原子完成（批次/槽位要么全建要么全不建）。
 * run_date UNIQUE：同日重复创建抛约束错，由调用方先 getBatch 分派复用。
 */
export function createBatchAndSlots(
  db: Database,
  runDate: string,
  totalSlots: number,
  slots: { slotIndex: number; difficulty: Difficulty; threadId: string }[],
): BatchRow {
  const tx = db.transaction((): BatchRow => {
    db.query("INSERT INTO article_batches (run_date, total_slots) VALUES (?, ?)").run(runDate, totalSlots);
    const stmt = db.query(
      `INSERT OR IGNORE INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id)
       VALUES (?, ?, ?, ?, ?)`,
    );
    const batchId = db.query("SELECT id FROM article_batches WHERE run_date = ?").get(runDate) as { id: number };
    for (const r of slots) {
      stmt.run(batchId.id, runDate, r.slotIndex, r.difficulty, r.threadId);
    }
    return getBatch(db, runDate)!;
  });
  return tx();
}

function toSlotRow(row: Record<string, unknown>): SlotRow {
  return {
    id: row.id as number,
    batchId: row.batch_id as number,
    runDate: row.run_date as string,
    slotIndex: row.slot_index as number,
    difficulty: row.difficulty as Difficulty,
    threadId: row.thread_id as string,
    status: row.status as SlotStatus,
    attempts: row.attempts as number,
    articleId: row.article_id as number | null,
    errorMessage: (row.error_message as string | null) ?? null,
  };
}

export function listSlots(db: Database, runDate: string): SlotRow[] {
  const rows = db
    .query("SELECT * FROM batch_slots WHERE run_date = ? ORDER BY slot_index ASC")
    .all(runDate) as Record<string, unknown>[];
  return rows.map(toSlotRow);
}

export function listFailedSlots(db: Database, runDate: string): SlotRow[] {
  return listSlots(db, runDate).filter((s) => s.status !== "success");
}

/**
 * 写槽位终态（thread_id 随行更新，场景一新 id 已在调用前写回）。
 * attempts 可选：缺省保留原值；图内校验重试后由 persistSlot 传入实际轮数（result.genAttempts）。
 */
export function writeSlotResult(
  db: Database,
  {
    slotId,
    threadId,
    status,
    articleId,
    attempts,
    errorMessage,
  }: {
    slotId: number;
    threadId: string;
    status: SlotStatus;
    articleId?: number;
    attempts?: number;
    /** 失败/拒绝原因（success 或不传 → null 清空，避免残留上个失败的原因）。 */
    errorMessage?: string | null;
  },
): void {
  db.query(
    `UPDATE batch_slots
     SET status = ?, thread_id = ?, article_id = COALESCE(?, article_id),
         attempts = COALESCE(?, attempts), error_message = ?, updated_at = datetime('now')
     WHERE id = ?`,
  ).run(status, threadId, articleId ?? null, attempts ?? null, errorMessage ?? null, slotId);
}

export interface RecentArticle {
  titleEn: string;
  category: Category;
  runDate: string;
  sourceUrl?: string;
}

/** 某 ISO 日期往前推 days 天的 ISO 日期（UTC 计算，无时区依赖）。 */
function isoDaysAgo(isoDate: string, days: number): string {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

/**
 * 最近 N 天（含 runDate 当天）成功发布的文章（仅 articles 有行 = success）。
 * 窗口 = runDate 往前 days-1 天；时间倒序；limit 截断（提示词块最多 60 条）。
 */
export function listRecentArticles(
  db: Database,
  runDate: string,
  days = 5,
  limit = 60,
): RecentArticle[] {
  const since = isoDaysAgo(runDate, days - 1);
  const rows = db
    .query(
      `SELECT title_en, category, run_date, source_url FROM articles
       WHERE run_date >= ? ORDER BY run_date DESC, id DESC LIMIT ?`,
    )
    .all(since, limit) as Record<string, unknown>[];
  return rows.map((r) => ({
    titleEn: r.title_en as string,
    category: r.category as Category,
    runDate: r.run_date as string,
    ...(r.source_url ? { sourceUrl: r.source_url as string } : {}),
  }));
}

/**
 * 事务写入：articles 一行 + 段落行。
 * 返回 article id；任一环节失败整体回滚。
 */
export function insertArticleWithParagraphs(
  db: Database,
  batchId: number,
  article: GeneratedArticle,
  threadId: string,
  markdownPath: string,
): number {
  const tx = db.transaction((a: GeneratedArticle): number => {
    if (a.paragraphs.length === 0) throw new Error("文章无段落，拒绝入库");
    const res = db
      .query(
        `INSERT INTO articles
           (batch_id, run_date, difficulty, category, path, source_url, title_en, title_zh,
            paragraph_count, markdown_path, thread_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        batchId,
        a.runDate,
        a.difficulty,
        a.category,
        a.path,
        a.sourceUrl ?? null,
        a.titleEn,
        a.titleZh,
        a.paragraphs.length,
        markdownPath,
        threadId,
      );
    const articleId = Number(res.lastInsertRowid);
    const stmt = db.query(
      `INSERT INTO article_paragraphs (article_id, paragraph_index, text_en, text_zh)
       VALUES (?, ?, ?, ?)`,
    );
    a.paragraphs.forEach((p, i) => stmt.run(articleId, i, p.en, p.zh));
    return articleId;
  });
  return tx(article);
}

export interface DeleteDailyCounts {
  batches: number;
  slots: number;
  articles: number;
  paragraphs: number;
}

/**
 * 删除某日全部数据（批次/槽位/文章/段落），单事务。
 * FK 未强制（PRAGMA foreign_keys = 0，见 docs/database-schema.md 注意 1），
 * 须按子表→父表顺序手动清理：paragraphs（经 article_id）→ articles → batch_slots → article_batches。
 */
export function deleteDailyData(db: Database, runDate: string): DeleteDailyCounts {
  const tx = db.transaction((): DeleteDailyCounts => {
    const paragraphs = db
      .query(
        "DELETE FROM article_paragraphs WHERE article_id IN (SELECT id FROM articles WHERE run_date = ?)",
      )
      .run(runDate).changes;
    const articles = db.query("DELETE FROM articles WHERE run_date = ?").run(runDate).changes;
    const slots = db.query("DELETE FROM batch_slots WHERE run_date = ?").run(runDate).changes;
    const batches = db.query("DELETE FROM article_batches WHERE run_date = ?").run(runDate).changes;
    return { batches, slots, articles, paragraphs };
  });
  return tx();
}

/** 收口批次：全 success → completed；否则 completed_with_failures；写计数与 finished_at。 */
export function finalizeBatch(db: Database, batchId: number): void {
  const batch = db.query("SELECT * FROM article_batches WHERE id = ?").get(batchId) as
    | Record<string, unknown>
    | undefined;
  if (!batch) return;
  const slots = db
    .query("SELECT status FROM batch_slots WHERE batch_id = ?")
    .all(batchId) as { status: string }[];
  if (slots.length === 0) return;
  const success = slots.filter((s) => s.status === "success").length;
  const failed = slots.filter((s) => s.status !== "success").length;
  const status = failed === 0 ? "completed" : "completed_with_failures";
  db.query(
    `UPDATE article_batches
     SET status = ?, completed_slots = ?, failed_slots = ?, finished_at = datetime('now')
     WHERE id = ?`,
  ).run(status, success, failed, batchId);
}
