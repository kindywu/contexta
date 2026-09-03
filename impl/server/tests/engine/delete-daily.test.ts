import { expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import type { Checkpoint } from "@langchain/langgraph-checkpoint";
import {
  deleteDailyData,
  ensureSchema,
  getBatch,
  createBatchAndSlots,
  insertArticleWithParagraphs,
  listSlots,
} from "../../src/engine/db";
import { BunSqliteCheckpointer } from "../../src/engine/graph/checkpointer";
import type { GeneratedArticle } from "../../src/engine/graph/state";

function articleFor(date: string, idx: number): GeneratedArticle {
  return {
    runDate: date,
    difficulty: "LOW",
    category: "daily_conversation",
    path: "B",
    titleEn: `T-${date}-${idx}`,
    titleZh: "中",
    paragraphs: [{ en: `en${idx}`, zh: `中${idx}` }],
  };
}

function count(db: Database, sql: string, ...args: string[]): number {
  return (db.query(sql).get(...args) as { c: number }).c;
}

test("deleteDailyData: 删当天四表数据、他天完整、返回计数", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  const b29 = createBatchAndSlots(db, "2026-08-29", 2, [
    { slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-29-0" },
    { slotIndex: 1, difficulty: "MEDIUM", threadId: "daily-2026-08-29-1" },
  ]);
  const b30 = createBatchAndSlots(db, "2026-08-30", 1, [{ slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-08-30-0" }]);
  insertArticleWithParagraphs(db, b29.id, articleFor("2026-08-29", 0), "daily-2026-08-29-0", "/tmp/a.md");
  insertArticleWithParagraphs(db, b29.id, articleFor("2026-08-29", 1), "daily-2026-08-29-1", "/tmp/b.md");
  insertArticleWithParagraphs(db, b30.id, articleFor("2026-08-30", 0), "daily-2026-08-30-0", "/tmp/c.md");

  const deleted = deleteDailyData(db, "2026-08-29");
  expect(deleted).toEqual({ batches: 1, slots: 2, articles: 2, paragraphs: 2 });

  // 当天清空
  expect(count(db, "SELECT count(*) AS c FROM article_batches WHERE run_date = ?", "2026-08-29")).toBe(0);
  expect(count(db, "SELECT count(*) AS c FROM batch_slots WHERE run_date = ?", "2026-08-29")).toBe(0);
  expect(count(db, "SELECT count(*) AS c FROM articles WHERE run_date = ?", "2026-08-29")).toBe(0);
  expect(count(db, "SELECT count(*) AS c FROM article_paragraphs")).toBe(1); // 只剩 30 日那篇
  // 他天完整
  expect(getBatch(db, "2026-08-30")).toBeDefined();
  expect(listSlots(db, "2026-08-30")).toHaveLength(1);
  expect(count(db, "SELECT count(*) AS c FROM articles WHERE run_date = ?", "2026-08-30")).toBe(1);
});

test("deleteDailyData: 无数据日期返回全 0", () => {
  const db = new Database(":memory:");
  ensureSchema(db);
  expect(deleteDailyData(db, "2026-08-31")).toEqual({ batches: 0, slots: 0, articles: 0, paragraphs: 0 });
});

async function seedCheckpoint(cp: BunSqliteCheckpointer, threadId: string, cid = "cid1"): Promise<void> {
  const checkpoint: Checkpoint = {
    v: 4,
    id: cid,
    ts: "2026-08-29T10:00:00.000Z",
    channel_values: {},
    channel_versions: {},
    versions_seen: {},
  };
  await cp.put({ configurable: { thread_id: threadId } }, checkpoint, {
    source: "input",
    step: 0,
    parents: {},
  });
  await cp.putWrites(
    { configurable: { thread_id: threadId, checkpoint_id: cid } },
    [["channel1", "value1"]],
    "task1",
  );
}

test("deleteThreadsByDate: 按 daily-<date>-% 删 checkpoints+writes，其他线程保留", async () => {
  const cp = new BunSqliteCheckpointer(":memory:");
  await seedCheckpoint(cp, "daily-2026-08-29-0");
  await seedCheckpoint(cp, "daily-2026-08-29-1", "cid2");
  await seedCheckpoint(cp, "daily-2026-08-29-0-2", "cid3"); // 旧格式历史线程
  await seedCheckpoint(cp, "daily-2026-08-30-0", "cid4");
  await seedCheckpoint(cp, "other-thread", "cid5");

  const deleted = await cp.deleteThreadsByDate("2026-08-29");
  expect(deleted).toEqual({ checkpoints: 3, writes: 3 });

  const remaining: string[] = [];
  for await (const t of cp.list({ configurable: {} })) {
    remaining.push(t.config.configurable?.thread_id as string);
  }
  expect(remaining.sort()).toEqual(["daily-2026-08-30-0", "other-thread"]);
});

test("deleteThreadsByDate: 无匹配线程时返回全 0、不误删", async () => {
  const cp = new BunSqliteCheckpointer(":memory:");
  await seedCheckpoint(cp, "daily-2026-08-30-0");

  expect(await cp.deleteThreadsByDate("2026-08-31")).toEqual({ checkpoints: 0, writes: 0 });
  const t = await cp.getTuple({ configurable: { thread_id: "daily-2026-08-30-0" } });
  expect(t).toBeDefined();
});
