import { expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import {
  ensureSchema, finalizeBatch, getBatch, createBatchAndSlots, insertArticleWithParagraphs,
  listFailedSlots, listRecentArticles, listSlots, writeSlotResult,
} from "../../src/engine/db";
import type { GeneratedArticle } from "../../src/engine/graph/state";

test("ensureSchema: 幂等（连跑两次不报错，表存在）", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureSchema(db);
  const names = db
    .query("SELECT name FROM sqlite_master WHERE type='table'")
    .all() as { name: string }[];
  expect(names.map((n) => n.name)).toContain("batch_slots");
  expect(names.map((n) => n.name)).toContain("articles");
  // articles 新列存在
  const cols = db.query("SELECT name FROM pragma_table_info('articles')").all() as { name: string }[];
  expect(cols.map((c) => c.name)).toContain("thread_id");
});

test("ensureSchema: 旧库补 thread_id 列", () => {
  const db = new Database(":memory:");
  db.exec(
    `CREATE TABLE articles (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       batch_id INTEGER NOT NULL, run_date TEXT NOT NULL, difficulty TEXT NOT NULL,
       category TEXT NOT NULL, path TEXT NOT NULL, source_url TEXT, title_en TEXT NOT NULL,
       title_zh TEXT NOT NULL, paragraph_count INTEGER NOT NULL, markdown_path TEXT NOT NULL,
       embedding BLOB NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))
     )`,
  );
  ensureSchema(db);
  const cols = db.query("SELECT name FROM pragma_table_info('articles')").all() as { name: string }[];
  expect(cols.map((c) => c.name)).toContain("thread_id");
});

test("createBatchAndSlots + getBatch: run_date UNIQUE 重复创建抛错，复用交给调用方 getBatch", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b1 = createBatchAndSlots(db, "2026-08-29", 3, []);
  expect(() => createBatchAndSlots(db, "2026-08-29", 3, [])).toThrow(); // UNIQUE 冲突，不再静默复用
  expect(getBatch(db, "2026-08-29")?.id).toBe(b1.id);
  expect(getBatch(db, "2026-08-30")).toBeUndefined();
});

test("createBatchAndSlots: 单事务建批次+槽位；同槽重复行 INSERT OR IGNORE", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 2, [
    { slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" },
    { slotIndex: 1, difficulty: "MEDIUM", threadId: "daily-2026-08-29-1" },
    { slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" }, // 同槽重复 → 忽略
  ]);
  expect(b.totalSlots).toBe(2);
  const slots = listSlots(db, "2026-08-29");
  expect(slots).toHaveLength(2);
  expect(slots[0]).toMatchObject({
    slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0", status: "pending", attempts: 1,
  });
});

test("listFailedSlots: 过滤 success；writeSlotResult 更新 status/articleId", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 2, [
    { slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" },
    { slotIndex: 1, difficulty: "LOW", threadId: "daily-2026-08-29-1" },
  ]);
  const [s0, s1] = listSlots(db, "2026-08-29")!;
  writeSlotResult(db, { slotId: s0!.id, threadId: s0!.threadId, status: "success", articleId: 7 });
  writeSlotResult(db, { slotId: s1!.id, threadId: s1!.threadId, status: "error" });
  const failed = listFailedSlots(db, "2026-08-29");
  expect(failed).toHaveLength(1);
  expect(failed[0]!.slotIndex).toBe(1);
  const slots = listSlots(db, "2026-08-29");
  expect(slots[0]).toMatchObject({ status: "success", articleId: 7 });
});

test("listRecentArticles: 5 天窗口（含当天/排除 6 天前）、倒序、limit", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 3, []);
  // 直接插文章行（与批次/槽位无关，测试里用裸 SQL 造数据）
  const ins = db.query(
    `INSERT INTO articles (batch_id, run_date, difficulty, category, path, title_en, title_zh,
       paragraph_count, markdown_path, thread_id)
     VALUES (?, ?, ?, ?, 'B', ?, ?, 1, 'output/x.md', ?)`,
  );
  ins.run(b.id, "2026-08-29", "LOW", "daily_conversation", "today", "今日", "t1");
  ins.run(b.id, "2026-08-25", "LOW", "simple_story", "day5", "第五天", "t2");
  ins.run(b.id, "2026-08-24", "LOW", "simple_story", "day6", "第六天", "t3");
  const out = listRecentArticles(db, "2026-08-29");
  expect(out.map((r) => r.titleEn)).toEqual(["today", "day5"]); // 含 8-25（往前 4 天），排除 8-24
  expect(out[0]).toEqual({
    titleEn: "today", category: "daily_conversation", runDate: "2026-08-29", sourceUrl: undefined,
  });
});

test("finalizeBatch: 全 success → completed；有失败 → completed_with_failures", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 2, [
    { slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" },
    { slotIndex: 1, difficulty: "LOW", threadId: "daily-2026-08-29-1" },
  ]);
  const [s0, s1] = listSlots(db, "2026-08-29")!;
  // writeSlotResult 为 Task 1 已提交的两参签名 (db, opts)，与第 74 行用法一致
  writeSlotResult(db, { slotId: s0!.id, threadId: s0!.threadId, status: "success", articleId: 1 });
  writeSlotResult(db, { slotId: s1!.id, threadId: s1!.threadId, status: "rejected" });
  finalizeBatch(db, b.id);
  const row = getBatch(db, "2026-08-29")!;
  expect(row.status).toBe("completed_with_failures");
  expect(row.completedSlots).toBe(1);
  expect(row.failedSlots).toBe(1);
});

const genArticle: GeneratedArticle = {
  runDate: "2026-08-29",
  difficulty: "LOW",
  category: "daily_conversation",
  path: "B",
  titleEn: "T", titleZh: "中",
  paragraphs: [
    { en: "para1 en", zh: "para1 中" },
    { en: "para2 en", zh: "para2 中" },
  ],
};

test("insertArticleWithParagraphs: 文章 + 段落 + thread_id 落库", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, []);
  const articleId = insertArticleWithParagraphs(db, b.id, genArticle, "daily-2026-08-29-0", "/tmp/x.md");
  const row = db.query("SELECT * FROM articles WHERE id = ?").get(articleId) as Record<string, unknown>;
  expect(row.thread_id).toBe("daily-2026-08-29-0");
  const paras = db.query("SELECT * FROM article_paragraphs WHERE article_id = ? ORDER BY paragraph_index").all(articleId) as { paragraph_index: number; text_en: string; text_zh: string }[];
  expect(paras).toHaveLength(2);
  expect(paras[0]).toMatchObject({ paragraph_index: 0, text_en: "para1 en", text_zh: "para1 中" });
});

test("insertArticleWithParagraphs: 中途抛错 → 事务回滚（无半写）", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b = createBatchAndSlots(db, "2026-08-29", 1, []);
  expect(() =>
    insertArticleWithParagraphs(db, b.id, { ...genArticle, paragraphs: [] }, "t", "x.md"),
  ).toThrow();
  const count = db.query("SELECT count(*) AS c FROM articles").get() as { c: number };
  expect(count.c).toBe(0);
  const paras = db.query("SELECT count(*) AS c FROM article_paragraphs").get() as { c: number };
  expect(paras.c).toBe(0);
});

test("ensureSchema: 旧库补 error_message 列（batch_slots）", () => {
  const db = new Database(":memory:");
  // 旧版 batch_slots（无 error_message）：ensureSchema 只补列，不重建表
  db.exec(`
    CREATE TABLE batch_slots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id INTEGER NOT NULL,
      run_date TEXT NOT NULL,
      slot_index INTEGER NOT NULL,
      difficulty TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','success','rejected','error')),
      attempts INTEGER NOT NULL DEFAULT 1,
      article_id INTEGER,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(batch_id, slot_index)
    )
  `);
  ensureSchema(db);
  const cols = db.query("SELECT name FROM pragma_table_info('batch_slots')").all() as { name: string }[];
  expect(cols.map((c) => c.name)).toContain("error_message");
});

test("writeSlotResult: errorMessage 落库，success 写回时清空", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  createBatchAndSlots(db, "2026-09-09", 1, [{ slotIndex: 0, difficulty: "LOW", threadId: "t" }]);
  const slot = listSlots(db, "2026-09-09")[0]!;
  writeSlotResult(db, { slotId: slot.id, threadId: slot.threadId, status: "error", attempts: 1, errorMessage: "LLM 超时" });
  expect(listSlots(db, "2026-09-09")[0]!.errorMessage).toBe("LLM 超时");
  // 成功写回不传 errorMessage → 清空（不残留上个失败的原因）
  writeSlotResult(db, { slotId: slot.id, threadId: slot.threadId, status: "success", attempts: 2 });
  expect(listSlots(db, "2026-09-09")[0]!.errorMessage).toBeNull();
  // 拒绝原因同样落库
  writeSlotResult(db, { slotId: slot.id, threadId: slot.threadId, status: "rejected", errorMessage: "抓取失败" });
  expect(listSlots(db, "2026-09-09")[0]!.errorMessage).toBe("抓取失败");
});
