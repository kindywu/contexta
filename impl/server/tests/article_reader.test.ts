// tests/article_reader.test.ts —— 重写为「投放路由」测试
// 算法单测在 article_delivery.test.ts；本文件只覆盖 HTTP 契约：鉴权/参数/键名。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureSchema, insertArticleWithParagraphs } from "../src/engine/db";
import { ensureServerSchema } from "../src/db";
import { loadServerConfig } from "../src/config";
import { articlesRouter } from "../src/routers/articles";
import { healthRouter } from "../src/routers/health";
import { authRouter } from "../src/routers/auth";

function seedOne(db: Database): number {
  ensureSchema(db);
  ensureServerSchema(db);
  db.run(`INSERT INTO article_batches (run_date, total_slots, status) VALUES ('2026-09-02', 1, 'completed')`);
  const id = insertArticleWithParagraphs(
    db, 1,
    { runDate: "2026-09-02", difficulty: "LOW", category: "simple_story", path: "B",
      titleEn: "T0", titleZh: "题0", paragraphs: [{ en: "para-en-0", zh: "para-zh-0" }] },
    "daily-2026-09-02-0", "/tmp/0.md",
  );
  db.query(`INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, article_id)
    VALUES (1, '2026-09-02', 0, 'LOW', 'th0', 'success', ?)`).run(id);
  db.query(`INSERT INTO article_review (article_id, slot_id, status, reviewed_by)
    VALUES (?, (SELECT id FROM batch_slots WHERE article_id = ?), 'approved', 'admin')`).run(id, id);
  return id;
}

describe("articles router (delivery)", () => {
  const cfg = loadServerConfig({ JWT_SECRET: "s".repeat(32), ADMIN_JWT_SECRET: "a".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" });
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
    const res = await app.request("/api/articles/delivery?difficulty=LOW&count=3");
    expect(res.status).toBe(401);
    expect((await res.json()).error_code).toBe("TOKEN_EXPIRED");
  });

  test("difficulty 非法 / count 缺失或 <1 → 400 BAD_PARAM", async () => {
    const db = new Database(":memory:");
    seedOne(db);
    const app = buildApp(db);
    const tok = await loginToken(app);
    const h = { authorization: `Bearer ${tok}` };
    for (const q of ["difficulty=XXX&count=3", "count=3", "difficulty=LOW", "difficulty=LOW&count=0", "difficulty=LOW&count=abc"]) {
      const res = await app.request(`/api/articles/delivery?${q}`, { headers: h });
      expect(res.status, `query=${q}`).toBe(400);
      expect((await res.json()).error_code, `query=${q}`).toBe("BAD_PARAM");
    }
  });

  test("GET /api/articles/delivery 返回投放集，键名 snake_case", async () => {
    const db = new Database(":memory:");
    seedOne(db);
    const app = buildApp(db);
    const tok = await loginToken(app);
    const res = await app.request("/api/articles/delivery?difficulty=LOW&count=3", {
      headers: { authorization: `Bearer ${tok}` },
    });
    expect(res.status).toBe(200);
    const raw = await res.text();
    for (const k of ['"target_date"', '"content_category"', '"order_index"', '"regenerate_count"', '"english_text"', '"chinese_translation"', '"delivery_date"']) {
      expect(raw).toContain(k);
    }
    expect(raw).not.toContain('"targetDate"');
    expect(raw).not.toContain('"deliveryDate"');
    const body = JSON.parse(raw);
    expect(body.code).toBe(0);
    expect(body.data.delivery_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(body.data.articles).toHaveLength(1);
    expect(body.data.articles[0]).toMatchObject({
      title: "T0", difficulty: "LOW", content_category: "simple_story",
      order_index: 1, regenerate_count: 0, status: "SUCCESS",
    });
  });

  test("旧端点已移除：/api/articles/today 与 /api/articles?date= → 404 NOT_FOUND", async () => {
    const db = new Database(":memory:");
    seedOne(db);
    const app = buildApp(db);
    const tok = await loginToken(app);
    const h = { authorization: `Bearer ${tok}` };
    for (const p of ["/api/articles/today", "/api/articles?date=2026-09-02"]) {
      const res = await app.request(p, { headers: h });
      expect(res.status, `path=${p}`).toBe(404);
    }
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
