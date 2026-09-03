// tests/article_reader.test.ts
// 文章下发读取（pipeline 库）：approved 过滤 + 字段映射 + orderIndex/regenerateCount 派生。
//
// 修正点（相对 brief）：brief 测试对同一 article 先插 rejected 再插 approved 两个 review 行，
// 违反 article_review.article_id UNIQUE。本测试按真实补生成（reRunSlot）语义建模：
// 槽位 0 首篇文章 review=rejected → 补生成新文章（review=approved，槽位改指新文章）——
// 旧 rejected 行保留，派生 regenerateCount = 该槽位 rejected 行数 = 1。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureSchema, insertArticleWithParagraphs, listSlots } from "../src/engine/db";
import { ensureServerSchema } from "../src/db";
import { listApprovedByDate } from "../src/services/article_reader";
import { loadServerConfig } from "../src/config";
import { articlesRouter } from "../src/routers/articles";
import { healthRouter } from "../src/routers/health";
import { authRouter } from "../src/routers/auth";
import type { Category, Difficulty } from "../src/engine/schema";
import type { GeneratedArticle } from "../src/engine/graph/state";

const mk = (slotIndex: number, difficulty: Difficulty, category: Category): GeneratedArticle => ({
  runDate: "2026-09-02", difficulty, category, path: "B", titleEn: `T${slotIndex}`, titleZh: `题${slotIndex}`,
  paragraphs: [{ en: `para-en-${slotIndex}`, zh: `para-zh-${slotIndex}` }],
});

function seed(db: Database): void {
  ensureSchema(db);
  ensureServerSchema(db);
  db.run(`INSERT INTO article_batches (run_date, total_slots, status) VALUES ('2026-09-02', 6, 'completed')`);
  const batchId = 1;
  const slots: { slotIndex: number; difficulty: Difficulty; threadId: string }[] = [
    { slotIndex: 0, difficulty: "LOW", threadId: "daily-2026-09-02-0" },
    { slotIndex: 1, difficulty: "LOW", threadId: "daily-2026-09-02-1" },
    { slotIndex: 2, difficulty: "MEDIUM", threadId: "daily-2026-09-02-2" },
    { slotIndex: 3, difficulty: "HIGH", threadId: "daily-2026-09-02-3" },
    // 4、5 留空模拟失败槽位
  ];
  for (const s of slots) {
    db.query(
      "INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status) VALUES (?, ?, ?, ?, ?, 'success')",
    ).run(batchId, "2026-09-02", s.slotIndex, s.difficulty, s.threadId);
  }
  for (const s of slots) {
    const id = insertArticleWithParagraphs(
      db, batchId, mk(s.slotIndex, s.difficulty, s.slotIndex === 0 ? "simple_story" : "news"),
      s.threadId, `/tmp/${s.slotIndex}.md`,
    );
    db.query(
      "UPDATE batch_slots SET article_id = ? WHERE id = (SELECT id FROM batch_slots WHERE batch_id=? AND slot_index=?)",
    ).run(id, batchId, s.slotIndex);
  }
}

describe("listApprovedByDate", () => {
  test("只返回 approved 且按难度/序号排序，regenerateCount 派生", () => {
    const db = new Database(":memory:");
    seed(db);
    // 首批文章均无 review 行 → 空；再为 slot0 制造 rejected 历史 + 补生成批准
    const slot0 = (listSlots(db, "2026-09-02").find((s) => s.slotIndex === 0))!;
    const slot0Article = slot0.articleId!;
    // 先制造一次 rejected 历史再批准：同槽位补生成新文章（新 review 行），旧 rejected 行保留
    db.query(
      "INSERT INTO article_review (article_id, slot_id, status, reject_reason, reviewed_by) VALUES (?, ?, 'rejected', 'r', 'admin')",
    ).run(slot0Article, slot0.id);
    const regenId = insertArticleWithParagraphs(
      db, 1, mk(0, "LOW", "simple_story"), "daily-2026-09-02-0-regen", "/tmp/0-regen.md",
    );
    db.query("UPDATE batch_slots SET article_id = ? WHERE id = ?").run(regenId, slot0.id);
    db.query(
      "INSERT INTO article_review (article_id, slot_id, status, reviewed_by) VALUES (?, ?, 'approved', 'admin')",
    ).run(regenId, slot0.id);
    const all = listApprovedByDate(db, "2026-09-02");
    expect(all).toHaveLength(1);
    expect(all[0].content_category).toBe("simple_story");
    expect(all[0].order_index).toBe(1);
    expect(all[0].regenerate_count).toBe(1);
    expect(all[0].paragraphs[0]).toEqual({ order_index: 1, english_text: "para-en-0", chinese_translation: "para-zh-0" });
    expect(all[0].status).toBe("SUCCESS");
    // 防回归：wire 键名必须精确 snake_case（App DTO article_dto.dart fromJson 按此解析）
    const wire = JSON.stringify(all[0]);
    for (const k of ['"target_date"', '"content_category"', '"order_index"', '"regenerate_count"', '"english_text"', '"chinese_translation"']) {
      expect(wire).toContain(k);
    }
    expect(wire).not.toContain('"targetDate"');
  });

  test("槽位 status 非 success（reRun 失败残留旧 approved 文章）不出现在结果中", () => {
    const db = new Database(":memory:");
    seed(db);
    const slot0 = (listSlots(db, "2026-09-02").find((s) => s.slotIndex === 0))!;
    db.query(
      "INSERT INTO article_review (article_id, slot_id, status, reviewed_by) VALUES (?, ?, 'approved', 'admin')",
    ).run(slot0.articleId, slot0.id);
    // article_id 指向已 approved 文章，但槽位终态非 success（模拟补生成失败残留）
    db.query("UPDATE batch_slots SET status = 'error' WHERE id = ?").run(slot0.id);
    const all = listApprovedByDate(db, "2026-09-02");
    expect(all).toHaveLength(0);
  });

  test("同难度 orderIndex 从 1 起派生；跨难度按 difficulty 字典序排列；无 rejected 历史 = 0", () => {
    const db = new Database(":memory:");
    seed(db);
    for (const s of listSlots(db, "2026-09-02")) {
      db.query(
        "INSERT INTO article_review (article_id, slot_id, status, reviewed_by) VALUES (?, ?, 'approved', 'admin')",
      ).run(s.articleId, s.id);
    }
    const all = listApprovedByDate(db, "2026-09-02");
    // 排序：difficulty ASCII 字典序（HIGH < LOW < MEDIUM），同难度按 orderIndex
    expect(all.map((a) => a.title)).toEqual(["T3", "T0", "T1", "T2"]);
    expect(all.map((a) => a.difficulty)).toEqual(["HIGH", "LOW", "LOW", "MEDIUM"]);
    expect(all.map((a) => a.order_index)).toEqual([1, 1, 2, 1]);
    expect(all[2].regenerate_count).toBe(0);
    expect(all[2].paragraphs[0]).toEqual({ order_index: 1, english_text: "para-en-1", chinese_translation: "para-zh-1" });
  });
});

describe("articles router", () => {
  const cfg = loadServerConfig({ JWT_SECRET: "s".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" });

  function buildApp(db: Database) {
    const app = articlesRouter(db, cfg);
    app.route("/", healthRouter());
    app.route("/", authRouter(db, cfg));
    return app;
  }

  async function loginToken(app: ReturnType<typeof buildApp>): Promise<string> {
    const res = await app.request("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13800000000", device_id: "dev1" }),
    });
    return (await res.json()).data.token;
  }

  test("无 token → 401 TOKEN_EXPIRED", async () => {
    const app = buildApp(new Database(":memory:"));
    const res = await app.request("/api/articles/today");
    expect(res.status).toBe(401);
    expect((await res.json()).error_code).toBe("TOKEN_EXPIRED");
  });

  test("GET /api/articles?date= 回 approved 文章；非法日期字符串 → 200 空数组（不 400）", async () => {
    const db = new Database(":memory:");
    seed(db);
    const app = buildApp(db);
    const tok = await loginToken(app);
    const slot0 = (listSlots(db, "2026-09-02").find((s) => s.slotIndex === 0))!;
    db.query(
      "INSERT INTO article_review (article_id, slot_id, status, reviewed_by) VALUES (?, ?, 'approved', 'admin')",
    ).run(slot0.articleId, slot0.id);
    const good = await app.request("/api/articles?date=2026-09-02", {
      headers: { authorization: `Bearer ${tok}` },
    });
    expect(good.status).toBe(200);
    // 防回归：c.json 序列化的真实响应体键名必须 snake_case（App DTO 契约）
    const raw = await good.text();
    for (const k of ['"target_date"', '"content_category"', '"order_index"', '"regenerate_count"', '"english_text"', '"chinese_translation"']) {
      expect(raw).toContain(k);
    }
    expect(raw).not.toContain('"targetDate"');
    const body = JSON.parse(raw);
    expect(body.code).toBe(0);
    expect(body.data).toHaveLength(1);
    expect(body.data[0]).toMatchObject({
      title: "T0", target_date: "2026-09-02", difficulty: "LOW", content_category: "simple_story",
      order_index: 1, regenerate_count: 0, status: "SUCCESS",
    });
    expect(body.data[0].paragraphs).toEqual([{ order_index: 1, english_text: "para-en-0", chinese_translation: "para-zh-0" }]);
    const bad = await app.request("/api/articles?date=not-a-date", {
      headers: { authorization: `Bearer ${tok}` },
    });
    expect(bad.status).toBe(200);
    expect((await bad.json()).data).toEqual([]);
  });

  test("GET /api/articles/today 无 date 默认配置时区的今天（不校验内容，仅形状）", async () => {
    const db = new Database(":memory:");
    ensureSchema(db); // 下发读取 pipeline 表 + login 会话表
    ensureServerSchema(db);
    const app = buildApp(db);
    const tok = await loginToken(app);
    const res = await app.request("/api/articles/today", {
      headers: { authorization: `Bearer ${tok}` },
    });
    expect(res.status).toBe(200);
    expect(Array.isArray((await res.json()).data)).toBe(true);
  });
});

describe("health router", () => {
  test("GET /api/health 无鉴权 → ok", async () => {
    const app = healthRouter();
    const res = await app.request("/api/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: { status: "ok" } });
  });
});
