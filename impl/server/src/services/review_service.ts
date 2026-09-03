// src/services/review_service.ts
// 审核服务（对齐架构文档 §5.3 审核状态机与 §6.2 迁移语义）：
// - ensureReviewRows：success 槽位且无 review 行的文章补 pending_review（INSERT OR IGNORE）
// - approveArticle：条件 UPDATE → approved；守卫"review 行存在 + 文章是槽位现指向"，
//   任一不满足或已非 pending_review → notFound（"不可过审 404"）
// - rejectArticle：同样守卫 + 条件 UPDATE → rejected / rejected_final；
//   未达 REGENERATE_LIMIT 时 await reRunSlot 原地补生成（管理端同步看到结果）
// - reRunSlot / retrySlot：槽位级进程锁内跑引擎生成，success 写 md + 入库 + 回填槽位，
//   失败只写槽位终态；收尾 finalizeBatch。
import type { Database } from "bun:sqlite";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import {
  finalizeBatch,
  insertArticleWithParagraphs,
  listRecentArticles,
  writeSlotResult,
  type SlotRow,
  type SlotStatus,
} from "../engine/db";
import { generateArticle } from "../engine/graph";
import { log } from "../engine/graph/log";
import type { ArticleResult } from "../engine/graph/state";
import type { Difficulty } from "../engine/schema";
import { renderMarkdown } from "../engine/render";
import { notFound } from "../response";

/** 生成入参（与引擎 GenerateArticleArgs 对齐；gen 缺省 = 引擎 generateArticle）。 */
export interface GenArgs {
  runDate: string;
  difficulty: Difficulty;
  threadId: string;
  config?: AppConfig;
  recentTitles?: string[];
  recentUsedUrls?: string[];
  usedUrls?: Set<string>;
}

/** 生成函数 seam（与引擎 LLM 接口并列）：测试注入假实现，生产用引擎 generateArticle。 */
export type GenFn = (args: GenArgs) => Promise<ArticleResult>;

export interface ReviewCtx {
  db: Database;
  serverCfg: ServerConfig;
  engineCfg: AppConfig;
  /** 生成函数 seam；缺省 = 引擎 generateArticle */
  gen?: GenFn;
}

/** 槽位级进程锁：同槽并发 reRun 串行（后到者等首跑完成再跑），键 = batch_slots.id。 */
const slotLocks = new Map<number, Promise<void>>();

async function withSlotLock(slotId: number, fn: () => Promise<void>): Promise<void> {
  const prev = slotLocks.get(slotId);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const next = (prev ?? Promise.resolve()).then(() => gate);
  slotLocks.set(slotId, next);
  try {
    if (prev) await prev; // 后到者等前一轮彻底结束（含收尾）
    await fn();
  } finally {
    release();
    // 无后续排队者时清掉条目（next 恒 resolve，链不因 fn 抛错断裂）
    if (slotLocks.get(slotId) === next) slotLocks.delete(slotId);
  }
}

/** 引擎 SlotRow 重建（与 engine/db.ts 的 toSlotRow 同形；引擎未导出，服务端不复用）。 */
export function toSlotRow(row: Record<string, unknown>): SlotRow {
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
  };
}

/**
 * 守卫查询：该文章有 review 行，且文章是 review.slot_id 所指向槽位的当前文章
 * （槽位现指向校验——重生成后旧文不再是当前文章，旧文不可再审）。
 * 任一不满足返回 undefined，调用方统一 notFound。
 */
function slotForArticle(db: Database, articleId: number): SlotRow | undefined {
  const review = db
    .query("SELECT slot_id FROM article_review WHERE article_id = ?")
    .get(articleId) as { slot_id: number } | undefined;
  if (!review) return undefined;
  const row = db
    .query("SELECT * FROM batch_slots WHERE id = ?")
    .get(review.slot_id) as Record<string, unknown> | undefined;
  if (!row) return undefined;
  return toSlotRow(row);
}

/**
 * 为所有 success 槽位且无 review 行的文章补 pending_review 行。
 * INSERT OR IGNORE（article_id UNIQUE）幂等：重跑不新增；返回本次新增行数。
 */
export function ensureReviewRows(db: Database): number {
  const res = db.run(
    `INSERT OR IGNORE INTO article_review (article_id, slot_id)
     SELECT s.article_id, s.id FROM batch_slots s
     WHERE s.status = 'success' AND s.article_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM article_review r WHERE r.article_id = s.article_id)`,
  );
  return Number(res.changes);
}

/**
 * 审核通过：pending_review 条件 UPDATE → approved。
 * 守卫（review 行存在 + 文章是槽位现指向）任一不满足、或已非 pending_review
 * （重复审核）→ notFound("article not reviewable")。
 */
export function approveArticle(db: Database, articleId: number, admin: string): void {
  const slot = slotForArticle(db, articleId);
  if (!slot || slot.articleId !== articleId) {
    throw notFound("article not reviewable");
  }
  const res = db
    .query(
      `UPDATE article_review
       SET status = 'approved', reviewed_by = ?, reviewed_at = datetime('now'),
           updated_at = datetime('now')
       WHERE article_id = ? AND status = 'pending_review'`,
    )
    .run(admin, articleId);
  if (res.changes === 0) {
    throw notFound("article not reviewable");
  }
}

/**
 * 审核拒绝：条件 UPDATE → rejected（达上限 → rejected_final）。
 * - 计数 n = 同槽累计 rejected 行数（不含本次，先数后写）；n < regenerateLimit
 *   → 写 rejected 并 await reRunSlot(ctx, slot, n + 1) 原地补生成（同步等，
 *   管理端看到结果）；n >= regenerateLimit → 写 rejected_final 不重生成。
 * - 并发重复拒绝：条件 UPDATE affected=0 → notFound（只建一条拒绝、只补一次）。
 * - reason 可空 → ''。
 */
export async function rejectArticle(
  ctx: ReviewCtx,
  articleId: number,
  reason: string | null | undefined,
  admin: string,
): Promise<void> {
  const { db, serverCfg } = ctx;
  const slot = slotForArticle(db, articleId);
  if (!slot || slot.articleId !== articleId) {
    throw notFound("article not reviewable");
  }
  const n = (
    db
      .query("SELECT COUNT(*) AS c FROM article_review WHERE slot_id = ? AND status = 'rejected'")
      .get(slot.id) as { c: number }
  ).c;
  const final = n >= serverCfg.regenerateLimit;
  const res = db
    .query(
      `UPDATE article_review
       SET status = ?, reject_reason = ?, reviewed_by = ?, reviewed_at = datetime('now'),
           updated_at = datetime('now')
       WHERE article_id = ? AND status = 'pending_review'`,
    )
    .run(final ? "rejected_final" : "rejected", reason ?? "", admin, articleId);
  if (res.changes === 0) {
    throw notFound("article not reviewable");
  }
  if (!final) {
    await reRunSlot(ctx, slot, n + 1);
  }
}

/**
 * 槽位重跑（拒绝补生成 / 失败重跑共用的引擎）：same-slot 串行（进程锁），
 * threadId = daily-<runDate>-<slotIndex>-r<genSeq>。
 * recent 上下文与引擎 daily 一致：listRecentArticles(db, runDate, 5, 60) 派生。
 * success → 写 md（失败直接抛，与引擎 persistSlot 语义一致）→ 入库 → 回填槽位
 * → ensureReviewRows 给新文补 pending_review；rejected/error → 只写槽位终态；
 * finally finalizeBatch。
 */
export async function reRunSlot(ctx: ReviewCtx, slotRow: SlotRow, genSeq: number): Promise<void> {
  await withSlotLock(slotRow.id, async () => {
    const { db, engineCfg } = ctx;
    const gen: GenFn = ctx.gen ?? generateArticle;
    const threadId = `daily-${slotRow.runDate}-${slotRow.slotIndex}-r${genSeq}`;
    const recent = listRecentArticles(db, slotRow.runDate, 5, 60);
    const recentTitles = recent.map((r) => r.titleEn);
    const recentUsedUrls = recent.flatMap((r) => (r.sourceUrl ? [r.sourceUrl] : []));
    // 引擎承诺返回三态不抛；但 checkpoint 路径不可用时会抛（BunSqliteCheckpointer
    // 构造在 try 外）。兜底按 error 落槽位终态不上抛——拒绝语义已完成，抛给管理端
    // 会被误读为"拒绝失败"（对齐旧版"补生成失败降级"决策）。
    let result: ArticleResult;
    try {
      result = await gen({
        runDate: slotRow.runDate,
        difficulty: slotRow.difficulty,
        threadId,
        config: engineCfg,
        recentTitles,
        recentUsedUrls,
        usedUrls: new Set<string>(),
      });
    } catch (e) {
      log(`reRunSlot slot=${slotRow.id} gen 抛错: ${e instanceof Error ? (e.stack ?? e.message) : String(e)}`);
      result = { outcome: "error", message: e instanceof Error ? e.message : String(e) };
    }
    try {
      if (result.outcome === "success") {
        const article = result.article;
        await mkdir(engineCfg.outputDir, { recursive: true });
        const file = join(
          engineCfg.outputDir,
          `${article.runDate}-${article.category}-${Date.now()}.md`,
        );
        await Bun.write(file, renderMarkdown(article));
        const articleId = insertArticleWithParagraphs(db, slotRow.batchId, article, threadId, file);
        writeSlotResult(db, {
          slotId: slotRow.id,
          threadId,
          status: "success",
          articleId,
          attempts: result.genAttempts,
        });
        ensureReviewRows(db); // 新文补 pending_review；旧文已有行（NOT EXISTS）跳过
        return;
      }
      const status: SlotStatus = result.outcome === "rejected" ? "rejected" : "error";
      writeSlotResult(db, { slotId: slotRow.id, threadId, status, attempts: result.genAttempts });
    } finally {
      finalizeBatch(db, slotRow.batchId);
    }
  });
}

/**
 * error/rejected 槽位（无文章）重跑入口。
 * genSeq = Date.now()（唯一线程号）：引擎同 threadId 已有终态 checkpoint 时按断点
 * 续跑契约返回旧结果、不重跑 LLM——固定 genSeq=1（thread 恒 -r1）会令"重复点重试"
 * 或"拒绝补生成失败后再重试"静默 no-op。唯一号永不与拒绝路径的 n+1 ∈ [1, REGENERATE_LIMIT]
 * 撞号；delete-daily 的 LIKE 'daily-<date>-%' 前缀仍连带清理 -r<Date.now()> 线程
 * （运行时进程锁保证同槽串行）。
 */
export function retrySlot(ctx: ReviewCtx, slotRow: SlotRow): Promise<void> {
  return reRunSlot(ctx, slotRow, Date.now());
}
