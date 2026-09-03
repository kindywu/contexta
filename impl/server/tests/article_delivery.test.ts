// tests/article_delivery.test.ts
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureServerSchema } from "../src/db";
import { ensureSchema, insertArticleWithParagraphs } from "../src/engine/db";
import {
  DEFAULT_ARTICLE_QUOTA_DAILY,
  deliverArticles,
  type DeliveryArgs,
} from "../src/services/article_delivery";
import type { Category, Difficulty } from "../src/engine/schema";

describe("article_delivery 表", () => {
  test("ensureServerSchema 幂等建表 + 唯一约束", () => {
    const db = new Database(":memory:");
    ensureSchema(db);
    ensureServerSchema(db);
    const cols = db
      .query("SELECT name FROM pragma_table_info('article_delivery')")
      .all() as { name: string }[];
    expect(cols.map((c) => c.name).sort()).toEqual([
      "article_id", "created_at", "delivery_date", "device_id",
      "difficulty", "id", "phone",
    ]);
    // 幂等：重复执行不报错
    ensureServerSchema(db);
    const idx = db
      .query("SELECT name FROM pragma_index_list('article_delivery')")
      .all() as { name: string }[];
    expect(idx.map((i) => i.name)).toContain(
      "sqlite_autoindex_article_delivery_1",
    );
  });
});

// ── 语料：09-01 LOW×3(id 1-3) MEDIUM×2(4-5)；09-02 LOW×2(6-7) MEDIUM×1(8)，全部 approved+success ──
function seedCorpus(db: Database): void {
  ensureSchema(db);
  ensureServerSchema(db);
  db.run(`INSERT INTO article_batches (run_date, total_slots, status) VALUES ('2026-09-01', 5, 'completed')`);
  const day1: { slot: number; d: Difficulty; cat: Category }[] = [
    { slot: 0, d: "LOW", cat: "simple_story" },
    { slot: 1, d: "LOW", cat: "simple_story" },
    { slot: 2, d: "LOW", cat: "simple_story" },
    { slot: 3, d: "MEDIUM", cat: "news" },
    { slot: 4, d: "MEDIUM", cat: "news" },
  ];
  for (const s of day1) {
    const id = insertArticleWithParagraphs(
      db, 1,
      { runDate: "2026-09-01", difficulty: s.d, category: s.cat, path: "B",
        titleEn: `T${s.slot}-day1`, titleZh: `题${s.slot}`,
        paragraphs: [{ en: `para-${s.slot}-1`, zh: `段-${s.slot}-1` }] },
      `daily-2026-09-01-${s.slot}`, `/tmp/${s.slot}.md`,
    );
    db.query(`INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, article_id)
      VALUES (1, '2026-09-01', ?, ?, ?, 'success', ?)`).run(s.slot, s.d, `daily-2026-09-01-${s.slot}`, id);
    db.query(`INSERT INTO article_review (article_id, slot_id, status, reviewed_by)
      VALUES (?, (SELECT id FROM batch_slots WHERE article_id = ?), 'approved', 'admin')`).run(id, id);
  }
  db.run(`INSERT INTO article_batches (run_date, total_slots, status) VALUES ('2026-09-02', 3, 'completed')`);
  const day2: { slot: number; d: Difficulty; cat: Category }[] = [
    { slot: 0, d: "LOW", cat: "scene_description" },
    { slot: 1, d: "LOW", cat: "scene_description" },
    { slot: 2, d: "MEDIUM", cat: "news" },
  ];
  for (const s of day2) {
    const id = insertArticleWithParagraphs(
      db, 2,
      { runDate: "2026-09-02", difficulty: s.d, category: s.cat, path: "B",
        titleEn: `T${s.slot}-day2`, titleZh: `题${s.slot}-day2`,
        paragraphs: [{ en: `para-${s.slot}-2`, zh: `段-${s.slot}-2` }] },
      `daily-2026-09-02-${s.slot}`, `/tmp/${s.slot}-2.md`,
    );
    db.query(`INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, article_id)
      VALUES (2, '2026-09-02', ?, ?, ?, 'success', ?)`).run(s.slot, s.d, `daily-2026-09-02-${s.slot}`, id);
    db.query(`INSERT INTO article_review (article_id, slot_id, status, reviewed_by)
      VALUES (?, (SELECT id FROM batch_slots WHERE article_id = ?), 'approved', 'admin')`).run(id, id);
  }
}

const now20260903 = new Date("2026-09-03T09:00:00+08:00").getTime();
const deliver = (db: Database, o: Partial<DeliveryArgs> & { difficulty: Difficulty; count: number }) =>
  deliverArticles(db, { phone: "13800000000", deviceId: "dev1", nowMs: now20260903, timeZone: "Asia/Shanghai", ...o });

describe("deliverArticles", () => {
  test("首次投放：最新 N 篇（id DESC）+ 交付内序号 + 账本记录", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const r = deliver(db, { difficulty: "LOW", count: 3 });
    expect(r.deliveryDate).toBe("2026-09-03");
    expect(r.articles.map((a) => a.id)).toEqual([7, 6, 3]); // id DESC 最新
    expect(r.articles.map((a) => a.order_index)).toEqual([1, 2, 3]);
    expect(r.articles[0]).toMatchObject({
      target_date: "2026-09-02", difficulty: "LOW",
      content_category: "scene_description", status: "SUCCESS", regenerate_count: 0,
    });
    const rows = db.query("SELECT article_id, delivery_date FROM article_delivery").all();
    expect(rows).toHaveLength(3);
  });

  test("新文章不足 → 补位最早未读（跳过已交付）", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    deliver(db, { difficulty: "LOW", count: 3 });       // 交付 [7,6,3]
    const r = deliver(db, { difficulty: "LOW", count: 3, nowMs: new Date("2026-09-04T09:00:00+08:00").getTime() });
    expect(r.deliveryDate).toBe("2026-09-04");
    expect(r.articles.map((a) => a.id)).toEqual([1, 2]); // 最新无（cursor=7）；补位最早未读，跳过 3/6/7
  });

  test("全部读完（无可投未读）→ 返回空，不重复已读文章", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    deliver(db, { difficulty: "LOW", count: 3 });                                  // 09-03: [7,6,3]
    deliver(db, { difficulty: "LOW", count: 3, nowMs: new Date("2026-09-04T09:00:00+08:00").getTime() }); // [1,2]
    // 09-05：LOW 5 篇全部交付过 → 无未读 → 空（不再重复）
    const r = deliver(db, { difficulty: "LOW", count: 2, nowMs: new Date("2026-09-05T09:00:00+08:00").getTime() });
    expect(r.articles).toEqual([]);
    // 空交付不记账：同日（09-05）服务端生成并批准新文章后可正常投放
    const id10 = insertArticleWithParagraphs(
      db, 2,
      { runDate: "2026-09-05", difficulty: "LOW", category: "simple_story", path: "B",
        titleEn: "T10", titleZh: "题10", paragraphs: [{ en: "p10", zh: "段10" }] },
      "daily-2026-09-05-10", "/tmp/10.md",
    );
    db.query(`INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, article_id)
      VALUES (2, '2026-09-05', 10, 'LOW', 'th10', 'success', ?)`).run(id10);
    db.query(`INSERT INTO article_review (article_id, slot_id, status, reviewed_by)
      VALUES (?, (SELECT id FROM batch_slots WHERE article_id = ?), 'approved', 'admin')`).run(id10, id10);
    const r2 = deliver(db, { difficulty: "LOW", count: 2, nowMs: new Date("2026-09-05T10:00:00+08:00").getTime() });
    expect(r2.deliveryDate).toBe("2026-09-05");
    expect(r2.articles.map((a) => a.id)).toEqual([id10]);
  });

  test("同日重复 → 冻结原集合（按账号；当日新文章不追加；换设备也读到同一批）", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const first = deliver(db, { difficulty: "LOW", count: 2 });
    expect(first.articles.map((a) => a.id)).toEqual([7, 6]);
    // 同日服务端生成并批准新文章 id=9
    const id9 = insertArticleWithParagraphs(
      db, 2,
      { runDate: "2026-09-03", difficulty: "LOW", category: "simple_story", path: "B",
        titleEn: "T9", titleZh: "题9", paragraphs: [{ en: "p9", zh: "段9" }] },
      "daily-2026-09-03-9", "/tmp/9.md",
    );
    db.query(`INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, article_id)
      VALUES (2, '2026-09-03', 9, 'LOW', 'th9', 'success', ?)`).run(id9);
    db.query(`INSERT INTO article_review (article_id, slot_id, status, reviewed_by)
      VALUES (?, (SELECT id FROM batch_slots WHERE article_id = ?), 'approved', 'admin')`).run(id9, id9);
    const again = deliver(db, { difficulty: "LOW", count: 2 });
    expect(again.articles.map((a) => a.id)).toEqual([7, 6]); // 冻结，不返回 9
    // 同账号换设备（dev2）同日再读 → 同一批原文章（"10:00 读到 9 点的文章"）
    const b = deliver(db, { difficulty: "LOW", count: 2, deviceId: "dev2" });
    expect(b.articles.map((a) => a.id)).toEqual([7, 6]);
  });

  test("delete-daily 删光冻结集的全部文章 → 不抛异常，落入全新投放路径", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const first = deliver(db, { difficulty: "LOW", count: 2 });
    expect(first.articles.map((a) => a.id)).toEqual([7, 6]); // 两者 run_date=2026-09-02
    // 模拟 delete-daily 删除 2026-09-02 全部文章（article_delivery 账本行残留，与 deleteDailyData 一致）
    db.run(`DELETE FROM article_paragraphs WHERE article_id IN (SELECT id FROM articles WHERE run_date = '2026-09-02')`);
    db.run(`DELETE FROM articles WHERE run_date = '2026-09-02'`);
    const again = deliver(db, { difficulty: "LOW", count: 2 });
    expect(again.deliveryDate).toBe("2026-09-03");
    // 全新投放：游标仍按账本 = 7；已删文章不复现；补位最早未读 [1, 2]
    expect(again.articles.map((a) => a.id)).toEqual([1, 2]);
    expect(again.articles.map((a) => a.order_index)).toEqual([1, 2]);
    // 同日再次调用 → 新投集合被冻结
    const frozen = deliver(db, { difficulty: "LOW", count: 2 });
    expect(frozen.articles.map((a) => a.id)).toEqual([1, 2]);
  });

  test("delete-daily 只删冻结集部分文章 → 按幸存者冻结返回（order_index 重排）", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const first = deliver(db, { difficulty: "LOW", count: 2 });
    expect(first.articles.map((a) => a.id)).toEqual([7, 6]);
    db.run(`DELETE FROM article_paragraphs WHERE article_id = 6`);
    db.run(`DELETE FROM articles WHERE id = 6`);
    const again = deliver(db, { difficulty: "LOW", count: 2 });
    expect(again.articles.map((a) => a.id)).toEqual([7]); // 删除的不返回，幸存者照常冻结
    expect(again.articles.map((a) => a.order_index)).toEqual([1]); // 1..N 重排
  });

  test("count 截断：quota 未设置 → 默认 5", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const r = deliver(db, { difficulty: "LOW", count: 10 });
    expect(r.articles).toHaveLength(DEFAULT_ARTICLE_QUOTA_DAILY);
    expect(r.articles.map((a) => a.id)).toEqual([7, 6, 3, 2, 1]);
  });

  test("count 截断：users.quota_article_daily 优先", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    db.query(`INSERT INTO users (phone, status, created_at, updated_at, quota_article_daily)
      VALUES ('13800000000', 'normal', 1, 1, 2)`).run();
    const r = deliver(db, { difficulty: "LOW", count: 5 });
    expect(r.articles).toHaveLength(2);
    expect(r.articles.map((a) => a.id)).toEqual([7, 6]);
  });

  test("空交付（无该难度文章）→ 空数组且不记账", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const r = deliver(db, { difficulty: "HIGH", count: 3 });
    expect(r.articles).toEqual([]);
    expect(db.query("SELECT COUNT(*) AS n FROM article_delivery").get()).toEqual({ n: 0 });
    // 同日稍后有文章 → 可以正常投放（不因空交付被冻结）
    const idH = insertArticleWithParagraphs(
      db, 2,
      { runDate: "2026-09-03", difficulty: "HIGH", category: "academic_abstract", path: "B",
        titleEn: "TH", titleZh: "题H", paragraphs: [{ en: "ph", zh: "段h" }] },
      "daily-2026-09-03-h", "/tmp/h.md",
    );
    db.query(`INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, article_id)
      VALUES (2, '2026-09-03', 99, 'HIGH', 'thh', 'success', ?)`).run(idH);
    db.query(`INSERT INTO article_review (article_id, slot_id, status, reviewed_by)
      VALUES (?, (SELECT id FROM batch_slots WHERE article_id = ?), 'approved', 'admin')`).run(idH, idH);
    const r2 = deliver(db, { difficulty: "HIGH", count: 3 });
    expect(r2.articles.map((a) => a.id)).toEqual([idH]);
  });

  test("契约回归：序列化键名 snake_case", () => {
    const db = new Database(":memory:");
    seedCorpus(db);
    const wire = JSON.stringify(deliver(db, { difficulty: "LOW", count: 1 }));
    for (const k of ['"target_date"', '"content_category"', '"order_index"',
                     '"regenerate_count"', '"english_text"', '"chinese_translation"']) {
      expect(wire).toContain(k);
    }
    expect(wire).not.toContain('"targetDate"');
  });
});
