// tests/review_service.test.ts
// 审核服务（服务端表独立建模）：ensureReviewRows / approveArticle / rejectArticle /
// reRunSlot / retrySlot。gen 一律注入假实现（不真调 LLM、不建 checkpoint）。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig, type AppConfig } from "../src/engine/config";
import { ensureSchema, listSlots } from "../src/engine/db";
import type { ArticleResult, GeneratedArticle } from "../src/engine/graph/state";
import {
  approveArticle,
  ensureReviewRows,
  rejectArticle,
  reRunSlot,
  retrySlot,
  type GenArgs,
  type ReviewCtx,
} from "../src/services/review_service";

const RUN_DATE = "2026-09-02";

function article(overrides: Partial<GeneratedArticle> = {}): GeneratedArticle {
  return {
    runDate: RUN_DATE,
    difficulty: "MEDIUM",
    category: "news",
    path: "A",
    titleEn: "Title",
    titleZh: "题",
    paragraphs: [{ en: "e1", zh: "z1" }],
    ...overrides,
  };
}

function setup(options: { gen?: (args: GenArgs) => Promise<ArticleResult> } = {}) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  db.query(
    "INSERT INTO article_batches (run_date, total_slots, status) VALUES (?, 2, 'completed')",
  ).run(RUN_DATE);
  const slotId = (
    db.query(
      `INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status)
       VALUES (1, ?, 0, 'MEDIUM', 'daily-2026-09-02-0', 'success') RETURNING id`,
    ).get(RUN_DATE) as { id: number }
  ).id;
  const serverCfg = loadServerConfig({
    JWT_SECRET: "s".repeat(32),
    LLM_API_KEY: "k",
    TIMEZONE: "Asia/Shanghai",
  });
  // checkpoint/outputDir 隔离到 /tmp 唯一目录：假 gen 不建 checkpointer，但
  // reRunSlot 成功路径会真实写 md 到 outputDir
  const dir = mkdtempSync(join(tmpdir(), "review-svc-"));
  const engineCfg: AppConfig = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" }),
    dbPath: ":memory:",
    checkpointPath: join(dir, "cp-test.sqlite"),
    outputDir: join(dir, "output"),
  };
  const ctx: ReviewCtx = { db, serverCfg, engineCfg, gen: options.gen };
  return { db, slotId, serverCfg, engineCfg, ctx };
}

/** 给槽位插入一篇 success 文章并回填 article_id（thread_id 可选覆盖）。 */
function insertSlotArticle(
  db: Database,
  slotId: number,
  opts: { titleEn?: string; threadId?: string; runDate?: string; sourceUrl?: string } = {},
): number {
  const id = (
    db.query(
      `INSERT INTO articles
         (batch_id, run_date, difficulty, category, path, source_url, title_en, title_zh,
          paragraph_count, markdown_path, thread_id)
       VALUES (1, ?, 'MEDIUM', 'news', 'A', ?, ?, '题', 1, '/tmp/a.md', ?) RETURNING id`,
    ).get(
      opts.runDate ?? RUN_DATE,
      opts.sourceUrl ?? null,
      opts.titleEn ?? "T",
      opts.threadId ?? "daily-2026-09-02-0",
    ) as { id: number }
  ).id;
  db.query("UPDATE batch_slots SET article_id = ? WHERE id = ?").run(id, slotId);
  return id;
}

/** 预插 n 条同槽 rejected 历史行（各自独立文章，模拟此前补生成历史）。 */
function seedRejectedHistory(db: Database, slotId: number, n: number): void {
  for (let i = 0; i < n; i++) {
    const id = (
      db.query(
        `INSERT INTO articles
           (batch_id, run_date, difficulty, category, path, title_en, title_zh,
            paragraph_count, markdown_path, thread_id)
         VALUES (1, ?, 'MEDIUM', 'news', 'A', ?, '题', 1, '/tmp/x.md', 'seed') RETURNING id`,
      ).get(RUN_DATE, `Old ${i}`) as { id: number }
    ).id;
    db.query(
      "INSERT INTO article_review (article_id, slot_id, status, reviewed_by, reviewed_at) VALUES (?, ?, 'rejected', 'admin', datetime('now'))",
    ).run(id, slotId);
  }
}

/** 成功 gen 假实现：记录 args，每次生成标题递增的新文。 */
function successGen() {
  const calls: GenArgs[] = [];
  const gen = async (args: GenArgs): Promise<ArticleResult> => {
    calls.push(args);
    return {
      outcome: "success",
      genAttempts: 1,
      article: { ...article({ titleEn: `New ${calls.length}` }) },
    };
  };
  return { gen, calls };
}

describe("review_service", () => {
  test("ensureReviewRows 为 success 槽位建 pending_review 且幂等", () => {
    const { db, slotId } = setup();
    const id = insertSlotArticle(db, slotId);
    expect(ensureReviewRows(db)).toBe(1);
    expect(ensureReviewRows(db)).toBe(0); // 幂等：重跑不新增
    const r = db
      .query("SELECT status FROM article_review WHERE article_id = ?")
      .get(id) as { status: string };
    expect(r.status).toBe("pending_review");
  });

  test("ensureReviewRows 只为当前槽位文章建行（旧文已有行不重插）", () => {
    const { db, slotId } = setup();
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    ensureReviewRows(db);
    // 槽位换指向新文（模拟 reject 重生成后）：旧文已有一行，新文补行
    const newId = insertSlotArticle(db, slotId, {
      titleEn: "New",
      threadId: "daily-2026-09-02-0-r1",
    });
    expect(ensureReviewRows(db)).toBe(1);
    const rows = db
      .query("SELECT article_id, status FROM article_review ORDER BY article_id")
      .all() as { article_id: number; status: string }[];
    expect(rows).toEqual([
      { article_id: oldId, status: "pending_review" },
      { article_id: newId, status: "pending_review" },
    ]);
  });

  test("rejectArticle: 拒绝后补生成（thread 含 -r1），槽位回填新文，旧文行保留为 rejected", async () => {
    const { gen, calls } = successGen();
    const { db, slotId, ctx } = setup({ gen });
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    ensureReviewRows(db);

    await rejectArticle(ctx, oldId, "太简单", "admin");

    // gen 被调用一次：thread = daily-<runDate>-<slotIndex>-r1，带引擎上下文
    expect(calls).toHaveLength(1);
    expect(calls[0]!.threadId).toBe("daily-2026-09-02-0-r1");
    expect(calls[0]!.runDate).toBe(RUN_DATE);
    expect(calls[0]!.difficulty).toBe("MEDIUM");
    expect(calls[0]!.config).toBe(ctx.engineCfg);
    expect(calls[0]!.usedUrls).toBeInstanceOf(Set);
    // 旧 review 行 → rejected（reason/by 落库）
    const oldReview = db
      .query("SELECT status, reject_reason, reviewed_by FROM article_review WHERE article_id = ?")
      .get(oldId) as { status: string; reject_reason: string; reviewed_by: string };
    expect(oldReview.status).toBe("rejected");
    expect(oldReview.reject_reason).toBe("太简单");
    expect(oldReview.reviewed_by).toBe("admin");
    // 槽位回填新文（thread 更新为 -r1）
    const slot = db
      .query("SELECT article_id, thread_id, status FROM batch_slots WHERE id = ?")
      .get(slotId) as { article_id: number; thread_id: string; status: string };
    expect(slot.status).toBe("success");
    expect(slot.thread_id).toBe("daily-2026-09-02-0-r1");
    expect(slot.article_id).not.toBe(oldId);
    // 新文有 pending_review 行；旧文行保留（rejected）——同槽双行建模
    const newReview = db
      .query("SELECT status FROM article_review WHERE article_id = ?")
      .get(slot.article_id) as { status: string };
    expect(newReview.status).toBe("pending_review");
    const accounts = db
      .query("SELECT COUNT(*) AS c FROM articles WHERE batch_id = 1")
      .get() as { c: number };
    expect(accounts.c).toBe(2);
  });

  test("rejectArticle: recent 上下文来自最近 5 天成功文章（titles + sourceUrls）", async () => {
    const { gen, calls } = successGen();
    const { db, slotId, ctx } = setup({ gen });
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    // 前一天的成功文章（5 天窗口内，独立插入，不占槽位）
    db.query(
      `INSERT INTO articles
         (batch_id, run_date, difficulty, category, path, source_url, title_en, title_zh,
          paragraph_count, markdown_path, thread_id)
       VALUES (1, '2026-09-01', 'MEDIUM', 'news', 'A', 'https://example.com/y', 'Yesterday', '昨日',
               1, '/tmp/y.md', 'daily-2026-09-01-0')`,
    ).run();
    ensureReviewRows(db);

    await rejectArticle(ctx, oldId, "", "admin");

    expect(calls[0]!.recentTitles).toContain("Yesterday");
    expect(calls[0]!.recentUsedUrls).toContain("https://example.com/y");
  });

  test("rejectArticle: 达上限（同槽 3 条 rejected 历史）→ rejected_final 且 gen 不调用", async () => {
    const { gen, calls } = successGen();
    const { db, slotId, ctx } = setup({ gen });
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    seedRejectedHistory(db, slotId, 3); // 此前 3 次拒绝（内部补生成）
    ensureReviewRows(db);

    await rejectArticle(ctx, oldId, "还是不行", "admin");

    expect(calls).toHaveLength(0); // 不重生成
    const r = db
      .query("SELECT status FROM article_review WHERE article_id = ?")
      .get(oldId) as { status: string };
    expect(r.status).toBe("rejected_final");
    // 槽位不动（仍指向旧文，状态 success）
    const slot = db
      .query("SELECT article_id, thread_id, status FROM batch_slots WHERE id = ?")
      .get(slotId) as { article_id: number; thread_id: string; status: string };
    expect(slot.article_id).toBe(oldId);
    expect(slot.thread_id).toBe("daily-2026-09-02-0");
  });

  test("rejectArticle: 边界（2 条历史）→ 第 3 次拒绝触发 -r3 补生成", async () => {
    const { gen, calls } = successGen();
    const { db, slotId, ctx } = setup({ gen });
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    seedRejectedHistory(db, slotId, 2);
    ensureReviewRows(db);

    await rejectArticle(ctx, oldId, "x", "admin");

    expect(calls).toHaveLength(1);
    expect(calls[0]!.threadId).toBe("daily-2026-09-02-0-r3");
  });

  test("rejectArticle: 并发重复拒绝 → 后到者 notFound，gen 仅一次", async () => {
    const { gen, calls } = successGen();
    const { db, slotId, ctx } = setup({ gen });
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    ensureReviewRows(db);

    const p1 = rejectArticle(ctx, oldId, "a", "admin");
    const p2 = rejectArticle(ctx, oldId, "b", "admin");
    await expect(p2).rejects.toThrow(/article not reviewable/);
    await p1;

    expect(calls).toHaveLength(1);
    const rows = db
      .query("SELECT COUNT(*) AS c FROM article_review WHERE slot_id = ? AND status = 'rejected'")
      .get(slotId) as { c: number };
    expect(rows.c).toBe(1);
  });

  test("approveArticle: pending_review 过审成功；重复过审 → notFound", () => {
    const { db, slotId } = setup();
    const id = insertSlotArticle(db, slotId);
    ensureReviewRows(db);

    approveArticle(db, id, "admin");

    const r = db
      .query("SELECT status, reviewed_by, reviewed_at FROM article_review WHERE article_id = ?")
      .get(id) as { status: string; reviewed_by: string; reviewed_at: string | null };
    expect(r.status).toBe("approved");
    expect(r.reviewed_by).toBe("admin");
    expect(r.reviewed_at).toBeTruthy();
    // 已审（非 pending_review）→ 404
    expect(() => approveArticle(db, id, "admin")).toThrow(/article not reviewable/);
  });

  test("approveArticle: 文章非槽位现指向（旧文）→ notFound", () => {
    const { db, slotId } = setup();
    const oldId = insertSlotArticle(db, slotId, { titleEn: "Old" });
    const newId = insertSlotArticle(db, slotId, {
      titleEn: "New",
      threadId: "daily-2026-09-02-0-r1",
    });
    ensureReviewRows(db);

    expect(() => approveArticle(db, oldId, "admin")).toThrow(/article not reviewable/);
    approveArticle(db, newId, "admin"); // 当前指向可过审
  });

  test("approveArticle: 无 review 行 → notFound", () => {
    const { db, slotId } = setup();
    const id = insertSlotArticle(db, slotId); // 未 ensureReviewRows
    expect(() => approveArticle(db, id, "admin")).toThrow(/article not reviewable/);
  });

  test("rejectArticle: 无 review 行 / 非现指向 → notFound", async () => {
    const { db, slotId, ctx } = setup();
    const id = insertSlotArticle(db, slotId); // 未 ensureReviewRows
    await expect(rejectArticle(ctx, id, "x", "admin")).rejects.toThrow(/article not reviewable/);
  });

  test("reRunSlot: 生成被拒 → 槽位终态 rejected + 批次收口 completed_with_failures", async () => {
    const gen = async (): Promise<ArticleResult> => ({
      outcome: "rejected",
      genAttempts: 2,
      reason: "不合规",
    });
    const { db, ctx } = setup({ gen });
    const slot = listSlots(db, RUN_DATE)[0]!;

    await reRunSlot(ctx, slot, 1);

    const s = db
      .query("SELECT status, thread_id, attempts FROM batch_slots WHERE id = ?")
      .get(slot.id) as { status: string; thread_id: string; attempts: number };
    expect(s.status).toBe("rejected");
    expect(s.thread_id).toBe("daily-2026-09-02-0-r1");
    expect(s.attempts).toBe(2);
    const batch = db.query("SELECT status FROM article_batches WHERE id = 1").get() as { status: string };
    expect(batch.status).toBe("completed_with_failures");
  });

  test("reRunSlot: 生成 error → 槽位终态 error", async () => {
    const gen = async (): Promise<ArticleResult> => ({ outcome: "error", message: "网络挂了" });
    const { db, ctx } = setup({ gen });
    const slot = listSlots(db, RUN_DATE)[0]!;

    await reRunSlot(ctx, slot, 2);

    const s = db.query("SELECT status, thread_id FROM batch_slots WHERE id = ?").get(slot.id) as {
      status: string;
      thread_id: string;
    };
    expect(s.status).toBe("error");
    expect(s.thread_id).toBe("daily-2026-09-02-0-r2");
  });

  test("reRunSlot: 同槽并发串行（进程锁），后到者等首跑", async () => {
    let inFlight = 0;
    let maxInFlight = 0;
    let calls = 0;
    const gen = async (args: GenArgs): Promise<ArticleResult> => {
      calls++;
      inFlight++;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((r) => setTimeout(r, 10));
      inFlight--;
      return { outcome: "success", genAttempts: 1, article: { ...article({ titleEn: `N${calls}` }) } };
    };
    const { db, ctx } = setup({ gen });
    const slot = listSlots(db, RUN_DATE)[0]!;

    const p1 = reRunSlot(ctx, slot, 1);
    const p2 = reRunSlot(ctx, slot, 2);
    await Promise.all([p1, p2]);

    expect(maxInFlight).toBe(1); // 从未并发进入 gen——槽位锁生效
    expect(calls).toBe(2);
    const threads = (
      db.query("SELECT thread_id FROM articles ORDER BY id").all() as { thread_id: string }[]
    ).map((r) => r.thread_id);
    expect(threads).toContain("daily-2026-09-02-0-r1");
    expect(threads).toContain("daily-2026-09-02-0-r2");
  });

  test("retrySlot: error 槽位（无文章）重跑入口 → genSeq=1（thread -r1）", async () => {
    const { gen, calls } = successGen();
    const { db, ctx } = setup({ gen });
    const slot = listSlots(db, RUN_DATE)[0]!;
    db.query("UPDATE batch_slots SET status = 'error' WHERE id = ?").run(slot.id);

    await retrySlot(ctx, slot);

    expect(calls).toHaveLength(1);
    expect(calls[0]!.threadId).toBe("daily-2026-09-02-0-r1");
    const s = db
      .query("SELECT status, article_id FROM batch_slots WHERE id = ?")
      .get(slot.id) as { status: string; article_id: number };
    expect(s.status).toBe("success");
    expect(s.article_id).not.toBeNull();
    // 新文有 pending_review
    const rev = db
      .query("SELECT status FROM article_review WHERE article_id = ?")
      .get(s.article_id) as { status: string };
    expect(rev.status).toBe("pending_review");
  });

  test("reRunSlot: 注入 gen 抛错 → 槽位按 error 落库且批次收口", async () => {
    const gen = async (): Promise<ArticleResult> => {
      throw new Error("checkpoint 目录不可写");
    };
    const { db, ctx } = setup({ gen });
    const slot = listSlots(db, RUN_DATE)[0]!;

    await expect(reRunSlot(ctx, slot, 1)).resolves.toBeUndefined(); // 不上抛（拒绝语义已完成）

    const s = db.query("SELECT status, thread_id FROM batch_slots WHERE id = ?").get(slot.id) as {
      status: string;
      thread_id: string;
    };
    expect(s.status).toBe("error");
    expect(s.thread_id).toBe("daily-2026-09-02-0-r1");
    const batch = db.query("SELECT status FROM article_batches WHERE id = 1").get() as { status: string };
    expect(batch.status).toBe("completed_with_failures");
  });
});
