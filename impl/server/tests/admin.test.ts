// tests/admin.test.ts
// 管理端 API（Task 8）：用户/配额/用量 + 槽位审核视图/详情/编辑 + 审核路由 + 手动补生成。
// 全部通过 app.request() 直连路由；gen/genDaily 一律注入假实现（不真调 LLM、不建 checkpoint）。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ensureServerSchema, seedAdminIfNeeded } from "../src/db";
import { loadServerConfig, type ServerConfig } from "../src/config";
import { loadConfig, type AppConfig } from "../src/engine/config";
import { createBatchAndSlots, ensureSchema, insertArticleWithParagraphs, listSlots, writeSlotResult } from "../src/engine/db";
import { adminRouter, type GenDailyFn } from "../src/routers/admin";
import { approveArticle } from "../src/services/review_service";
import { todayStartMillis } from "../src/time";
import type { ArticleResult, GeneratedArticle } from "../src/engine/graph/state";
import type { GenArgs } from "../src/services/review_service";
import type { Difficulty } from "../src/engine/schema";

const RUN_DATE = "2026-09-02";

const cfg: ServerConfig = loadServerConfig({
  JWT_SECRET: "s".repeat(32),
  LLM_API_KEY: "k",
  TIMEZONE: "Asia/Shanghai",
});

/** 测试引擎配置（字面量，不依赖 .env；outputDir 隔离到 /tmp 唯一目录——注入 gen 成功路径会真写 md）。 */
function testEngineCfg(dir: string): AppConfig {
  return {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" }),
    dbPath: ":memory:",
    checkpointPath: join(dir, "cp.sqlite"),
    outputDir: join(dir, "output"),
  };
}

interface SeedSlot {
  slotIndex: number;
  difficulty: Difficulty;
  status: "success" | "error" | "rejected" | "pending";
}

/** 建批次 + 槽位（createBatchAndSlots）+ 成功槽位插文回填（insertArticleWithParagraphs + writeSlotResult）。 */
function seedDay(db: Database, slots: SeedSlot[], date = RUN_DATE): void {
  const batch = createBatchAndSlots(
    db,
    date,
    slots.length,
    slots.map((s) => ({ slotIndex: s.slotIndex, difficulty: s.difficulty, threadId: `daily-${date}-${s.slotIndex}` })),
  );
  for (const s of slots) {
    const row = listSlots(db, date).find((r) => r.slotIndex === s.slotIndex)!;
    if (s.status === "success") {
      const id = insertArticleWithParagraphs(
        db,
        batch.id,
        {
          runDate: date,
          difficulty: s.difficulty,
          category: "news",
          path: "A",
          titleEn: `T${s.slotIndex}`,
          titleZh: `题${s.slotIndex}`,
          paragraphs: [
            { en: `en-${s.slotIndex}-1`, zh: `zh-${s.slotIndex}-1` },
            { en: `en-${s.slotIndex}-2`, zh: `zh-${s.slotIndex}-2` },
          ],
        },
        `daily-${date}-${s.slotIndex}`,
        `/tmp/${date}-${s.slotIndex}.md`,
      );
      writeSlotResult(db, { slotId: row.id, threadId: row.threadId, status: "success", articleId: id, attempts: 1 });
    } else {
      writeSlotResult(db, { slotId: row.id, threadId: row.threadId, status: s.status, attempts: 1 });
    }
  }
}

/** 给已成功槽位插一篇新文并回填槽位（模拟 reject 补生成后的新文章）。 */
function insertReplacementArticle(
  db: Database,
  slotId: number,
  opts: { titleEn?: string; threadId?: string } = {},
): number {
  const slot = db.query("SELECT * FROM batch_slots WHERE id = ?").get(slotId) as Record<string, unknown>;
  const id = insertArticleWithParagraphs(
    db,
    slot.batch_id as number,
    {
      runDate: slot.run_date as string,
      difficulty: slot.difficulty as Difficulty,
      category: "news",
      path: "A",
      titleEn: opts.titleEn ?? "Replacement",
      titleZh: "替换题",
      paragraphs: [{ en: "re-en", zh: "re-zh" }],
    },
    opts.threadId ?? `daily-${slot.run_date}-${slot.slot_index}-r1`,
    `/tmp/replace.md`,
  );
  db.query("UPDATE batch_slots SET article_id = ? WHERE id = ?").run(id, slotId);
  return id;
}

/** 成功 gen 假实现：记录 args，每次生成标题递增的新文（对齐 Task 7 手法）。 */
function successGen() {
  const calls: GenArgs[] = [];
  const gen = async (args: GenArgs): Promise<ArticleResult> => {
    calls.push(args);
    return {
      outcome: "success",
      genAttempts: 1,
      article: {
        runDate: args.runDate,
        difficulty: args.difficulty,
        category: "news",
        path: "A",
        titleEn: `New ${calls.length}`,
        titleZh: "新题",
        paragraphs: [{ en: "ne-en", zh: "ne-zh" }],
      },
    };
  };
  return { gen, calls };
}

async function buildApp(opts: { gen?: (args: GenArgs) => Promise<ArticleResult>; genDaily?: GenDailyFn } = {}) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  await seedAdminIfNeeded(db, "admin", "pw-123456");
  const dir = mkdtempSync(join(tmpdir(), "admin-"));
  const engineCfg = testEngineCfg(dir);
  const app = adminRouter(db, cfg, engineCfg, opts);
  return { db, app, engineCfg };
}

async function adminToken(app: Awaited<ReturnType<typeof buildApp>>["app"]): Promise<string> {
  const res = await app.request("/api/admin/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "admin", password: "pw-123456" }),
  });
  return (await res.json()).data.token;
}

function authHeader(tok: string): Record<string, string> {
  return { authorization: `Bearer ${tok}` };
}

describe("admin login", () => {
  test("密码错误/用户名不存在 → 401 INVALID_CREDENTIALS（不区分，防枚举；不再误报 TOKEN_EXPIRED）", async () => {
    const { app } = await buildApp();
    // 密码错误
    const badPw = await app.request("/api/admin/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "wrong" }),
    });
    expect(badPw.status).toBe(401);
    const badBody = await badPw.json();
    expect(badBody.error_code).toBe("INVALID_CREDENTIALS");
    expect(badBody.code).toBe(401);
    // 用户名不存在（与密码错误同响应，不区分）
    const noUser = await app.request("/api/admin/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "nobody", password: "x" }),
    });
    expect(noUser.status).toBe(401);
    expect((await noUser.json()).error_code).toBe("INVALID_CREDENTIALS");
  });

  test("正确凭据仍 200 + token（防回归）", async () => {
    const { app } = await buildApp();
    const res = await app.request("/api/admin/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "pw-123456" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.code).toBe(0);
    expect(typeof body.data.token).toBe("string");
  });
});

describe("admin users & usage", () => {
  test("用户列表：按 created_at 升序，today_word_lookups 只计今日 word_lookup", async () => {
    const { db, app } = await buildApp();
    const start = todayStartMillis(cfg.timeZone);
    db.query("INSERT INTO users (phone, status, created_at, updated_at) VALUES ('u1', 'normal', 1000, 1000)").run();
    db.query(
      "INSERT INTO users (phone, status, banned_reason, created_at, updated_at) VALUES ('u2', 'banned', 'spam', 2000, 2000)",
    ).run();
    // u1 今日 2 次 word_lookup + 昨日 1 次（不计）+ 今日非查词端点（不计入查词数）
    db.query(
      "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES ('u1', 'word_lookup', 10, 1, 5, ?)",
    ).run(start + 100);
    db.query(
      "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES ('u1', 'word_lookup', 20, 2, 5, ?)",
    ).run(start + 200);
    db.query(
      "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES ('u1', 'word_lookup', 99, 99, 5, ?)",
    ).run(start - 1);
    db.query(
      "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES ('u1', 'other', 30, 3, 5, ?)",
    ).run(start + 300);
    db.query(
      "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES ('u2', 'word_lookup', 40, 4, 5, ?)",
    ).run(start + 400);

    const tok = await adminToken(app);
    const res = await app.request("/api/admin/users", { headers: authHeader(tok) });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      code: 0,
      data: [
        { phone: "u1", status: "normal", banned_reason: null, created_at: 1000, quota_word_daily: null, today_word_lookups: 2 },
        { phone: "u2", status: "banned", banned_reason: "spam", created_at: 2000, quota_word_daily: null, today_word_lookups: 1 },
      ],
    });
  });

  test("ban/unban/quota：状态与配额落库、updated_at 刷新", async () => {
    const { db, app } = await buildApp();
    db.query("INSERT INTO users (phone, status, created_at, updated_at) VALUES ('u1', 'normal', 1000, 1000)").run();
    const tok = await adminToken(app);

    // ban 带 reason
    const ban = await app.request("/api/admin/users/u1/ban", {
      method: "POST", headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({ reason: "刷接口" }),
    });
    expect(ban.status).toBe(200);
    let row = db.query("SELECT status, banned_reason, updated_at FROM users WHERE phone = 'u1'").get() as {
      status: string; banned_reason: string | null; updated_at: number;
    };
    expect(row.status).toBe("banned");
    expect(row.banned_reason).toBe("刷接口");
    expect(row.updated_at).toBeGreaterThan(1000);

    // ban 不带 reason → 记录 NULL
    await app.request("/api/admin/users/u1/ban", {
      method: "POST", headers: authHeader(tok),
    });
    const afterBanNoReason = db.query("SELECT banned_reason FROM users WHERE phone = 'u1'").get() as { banned_reason: string | null };
    expect(afterBanNoReason.banned_reason).toBeNull();

    // unban → normal + reason NULL
    const unban = await app.request("/api/admin/users/u1/unban", { method: "POST", headers: authHeader(tok) });
    expect(unban.status).toBe(200);
    const afterUnban = db.query("SELECT status, banned_reason FROM users WHERE phone = 'u1'").get() as {
      status: string; banned_reason: string | null;
    };
    expect(afterUnban.status).toBe("normal");
    expect(afterUnban.banned_reason).toBeNull();

    // quota 覆盖
    const set = await app.request("/api/admin/users/u1/quota", {
      method: "PUT", headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({ word_daily: 500 }),
    });
    expect(set.status).toBe(200);
    expect((db.query("SELECT quota_word_daily FROM users WHERE phone = 'u1'").get() as { quota_word_daily: number | null }).quota_word_daily).toBe(500);
    // null = 清覆盖
    const clear = await app.request("/api/admin/users/u1/quota", {
      method: "PUT", headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({ word_daily: null }),
    });
    expect(clear.status).toBe(200);
    expect((db.query("SELECT quota_word_daily FROM users WHERE phone = 'u1'").get() as { quota_word_daily: number | null }).quota_word_daily).toBeNull();
  });

  test("quota 校验：word_daily 非正整数/非 number/缺失 → 400 BAD_PARAM 且不落库", async () => {
    const { db, app } = await buildApp();
    db.query("INSERT INTO users (phone, status, created_at, updated_at) VALUES ('u1', 'normal', 1000, 1000)").run();
    const tok = await adminToken(app);
    const put = (body: unknown) =>
      app.request("/api/admin/users/u1/quota", {
        method: "PUT",
        headers: { ...authHeader(tok), "content-type": "application/json" },
        body: JSON.stringify(body),
      });
    // "abc" 曾是重灾场景：SQLite TEXT 存储 → usage >= 'abc' 恒 false → 配额永久失效
    const badBodies = [
      { word_daily: "abc" },
      { word_daily: "500" },
      { word_daily: 1.5 },
      { word_daily: 0 },
      { word_daily: -5 },
      { word_daily: true },
      { word_daily: [1] },
      { word_daily: {} },
      {}, // 缺失字段同样拒绝（显式 null 才表示清覆盖）
    ];
    for (const body of badBodies) {
      const res = await put(body);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect((await res.json()).error_code).toBe("BAD_PARAM");
    }
    // 非法值零写入：quota 仍 NULL（防 TEXT 污染）
    const row = db.query("SELECT quota_word_daily FROM users WHERE phone = 'u1'").get() as {
      quota_word_daily: unknown;
    };
    expect(row.quota_word_daily).toBeNull();
    // 合法值（正整数 / null）仍可写（回归）
    expect((await put({ word_daily: 500 })).status).toBe(200);
    expect((await put({ word_daily: null })).status).toBe(200);
  });

  test("usage 汇总：按 (phone, endpoint) 聚合今日，含 NULL phone 独立成组", async () => {
    const { db, app } = await buildApp();
    const start = todayStartMillis(cfg.timeZone);
    const ins = (phone: string | null, endpoint: string, p: number, c: number, at: number) =>
      db.query(
        "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES (?, ?, ?, ?, 0, ?)",
      ).run(phone, endpoint, p, c, at);
    ins("u1", "word_lookup", 10, 1, start + 100);
    ins("u1", "word_lookup", 20, 2, start + 200);
    ins("u1", "article_generate", 5, 5, start + 300);
    ins("u1", "word_lookup", 99, 99, start - 1); // 昨日：不计
    ins("u2", "word_lookup", 7, 7, start + 400);
    ins(null, "daily_generate", 1, 1, start + 500);

    const tok = await adminToken(app);
    const res = await app.request("/api/admin/usage", { headers: authHeader(tok) });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      code: 0,
      data: [
        { phone: null, endpoint: "daily_generate", calls: 1, prompt_tokens: 1, completion_tokens: 1 },
        { phone: "u1", endpoint: "article_generate", calls: 1, prompt_tokens: 5, completion_tokens: 5 },
        { phone: "u1", endpoint: "word_lookup", calls: 2, prompt_tokens: 30, completion_tokens: 3 },
        { phone: "u2", endpoint: "word_lookup", calls: 1, prompt_tokens: 7, completion_tokens: 7 },
      ],
    });
  });

  test("全部端点（除 login）无 token → 401 TOKEN_EXPIRED", async () => {
    const { app } = await buildApp();
    for (const [method, path, body] of [
      ["GET", "/api/admin/users", undefined],
      ["POST", "/api/admin/users/u1/ban", {}],
      ["POST", "/api/admin/users/u1/unban", undefined],
      ["PUT", "/api/admin/users/u1/quota", {}],
      ["GET", "/api/admin/usage", undefined],
      ["GET", "/api/admin/articles?date=2026-09-02", undefined],
      ["GET", "/api/admin/articles/1", undefined],
      ["PUT", "/api/admin/articles/1", {}],
      ["POST", "/api/admin/articles/1/approve", undefined],
      ["POST", "/api/admin/articles/1/reject", {}],
      ["POST", "/api/admin/slots/1/retry", undefined],
      ["POST", "/api/admin/articles/generate", {}],
    ] as const) {
      const res = await app.request(path, { method, headers: { "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
      expect(res.status, `${method} ${path}`).toBe(401);
      expect((await res.json()).error_code).toBe("TOKEN_EXPIRED");
    }
  });
});

describe("admin articles slot view", () => {
  test("槽位视图：error 槽（无文章）出现且 article/review 为 null；success 槽带文章与 pending_review", async () => {
    const { db, app } = await buildApp();
    seedDay(db, [
      { slotIndex: 0, difficulty: "MEDIUM", status: "success" },
      { slotIndex: 1, difficulty: "LOW", status: "error" },
    ]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(db);
    const slots = listSlots(db, RUN_DATE);
    const tok = await adminToken(app);

    const res = await app.request(`/api/admin/articles?date=${RUN_DATE}`, { headers: authHeader(tok) });
    expect(res.status).toBe(200);
    const data = (await res.json()).data;
    expect(data).toHaveLength(2);
    // 0 槽：success + 文章 + pending_review
    expect(data[0]).toMatchObject({
      slot_id: slots[0]!.id,
      slot_index: 0,
      difficulty: "MEDIUM",
      status: "success",
      attempts: 1,
      thread_id: "daily-2026-09-02-0",
      article: {
        id: slots[0]!.articleId,
        category: "news",
        title_en: "T0",
        title_zh: "题0",
        source_url: null,
        paragraph_count: 2,
        path: "A",
        run_date: RUN_DATE,
      },
      review: { id: expect.any(Number), status: "pending_review", reject_reason: null, reviewed_by: null, reviewed_at: null },
    });
    expect(data[0].history).toEqual([
      { article_id: slots[0]!.articleId, status: "pending_review", reject_reason: null, reviewed_by: null, reviewed_at: null },
    ]);
    // 1 槽：error，无文章无 review
    expect(data[1]).toEqual({
      slot_id: slots[1]!.id,
      slot_index: 1,
      difficulty: "LOW",
      status: "error",
      attempts: 1,
      thread_id: "daily-2026-09-02-1",
      article: null,
      review: null,
      history: [],
    });
  });

  test("槽位视图：history 为同槽全部 review 行倒序（新 → 旧）", async () => {
    const { db, app } = await buildApp();
    seedDay(db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "success" }]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    const slot = listSlots(db, RUN_DATE)[0]!;
    const oldId = slot.articleId!;
    // 旧文 rejected（模拟此前补生成拒绝）
    db.query(
      "INSERT INTO article_review (article_id, slot_id, status, reject_reason, reviewed_by) VALUES (?, ?, 'rejected', '太简单', 'admin')",
    ).run(oldId, slot.id);
    // 槽位换指新文，新文补 pending_review
    const newId = insertReplacementArticle(db, slot.id, { threadId: "daily-2026-09-02-0-r1" });
    ensureReviewRows(db);
    const tok = await adminToken(app);

    const res = await app.request(`/api/admin/articles?date=${RUN_DATE}`, { headers: authHeader(tok) });
    const data = (await res.json()).data;
    expect(data).toHaveLength(1);
    expect(data[0].article).toMatchObject({ id: newId });
    expect(data[0].review).toMatchObject({ status: "pending_review" });
    // 倒序：新文行在前，旧文 rejected 行在后
    expect(data[0].history.map((h: { article_id: number; status: string }) => [h.article_id, h.status])).toEqual([
      [newId, "pending_review"],
      [oldId, "rejected"],
    ]);
  });

  test("槽位视图：status 过滤——pending_review 只出待审槽，'error' 只出 error 槽，approved 无匹配为空", async () => {
    const { db, app } = await buildApp();
    seedDay(db, [
      { slotIndex: 0, difficulty: "MEDIUM", status: "success" },
      { slotIndex: 1, difficulty: "LOW", status: "error" },
    ]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(db);
    const tok = await adminToken(app);

    const pending = await app.request(`/api/admin/articles?date=${RUN_DATE}&status=pending_review`, { headers: authHeader(tok) });
    const pendingData = (await pending.json()).data as { slot_index: number }[];
    expect(pendingData.map((s) => s.slot_index)).toEqual([0]);

    const err = await app.request(`/api/admin/articles?date=${RUN_DATE}&status=error`, { headers: authHeader(tok) });
    const errData = (await err.json()).data as { slot_index: number }[];
    expect(errData.map((s) => s.slot_index)).toEqual([1]);

    const approved = await app.request(`/api/admin/articles?date=${RUN_DATE}&status=approved`, { headers: authHeader(tok) });
    expect((await approved.json()).data).toEqual([]);
  });
});

describe("admin article detail", () => {
  test("详情：段落 order_index 1 起 + review/slot 字段；防回归 snake_case", async () => {
    const { db, app } = await buildApp();
    seedDay(db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "success" }]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(db);
    const articleId = listSlots(db, RUN_DATE)[0]!.articleId!;
    const tok = await adminToken(app);

    const res = await app.request(`/api/admin/articles/${articleId}`, { headers: authHeader(tok) });
    expect(res.status).toBe(200);
    const body = await res.json();
    const raw = await (await app.request(`/api/admin/articles/${articleId}`, { headers: authHeader(tok) })).text();
    for (const k of ['"title_en"', '"title_zh"', '"paragraph_count"', '"source_url"', '"order_index"', '"english_text"', '"chinese_translation"', '"slot_id"', '"slot_index"', '"run_date"']) {
      expect(raw).toContain(k);
    }
    expect(raw).not.toContain('"titleEn"');
    expect(body.data).toMatchObject({
      id: articleId,
      batch_id: 1,
      run_date: RUN_DATE,
      difficulty: "MEDIUM",
      category: "news",
      title_en: "T0",
      title_zh: "题0",
      path: "A",
      source_url: null,
      paragraph_count: 2,
      markdown_path: `/tmp/${RUN_DATE}-0.md`,
      thread_id: "daily-2026-09-02-0",
      review: { status: "pending_review" },
      slot_id: listSlots(db, RUN_DATE)[0]!.id,
      slot_index: 0,
    });
    expect(body.data.paragraphs).toEqual([
      { order_index: 1, english_text: "en-0-1", chinese_translation: "zh-0-1" },
      { order_index: 2, english_text: "en-0-2", chinese_translation: "zh-0-2" },
    ]);
  });

  test("详情：不存在 → 404 NOT_FOUND", async () => {
    const { app } = await buildApp();
    const tok = await adminToken(app);
    const res = await app.request("/api/admin/articles/999999", { headers: authHeader(tok) });
    expect(res.status).toBe(404);
    expect((await res.json()).error_code).toBe("NOT_FOUND");
  });
});

describe("admin article edit", () => {
  async function seedPendingArticle() {
    const built = await buildApp();
    seedDay(built.db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "success" }]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(built.db);
    const articleId = listSlots(built.db, RUN_DATE)[0]!.articleId!;
    return { ...built, articleId };
  }

  test("pending_review 可编辑：title_en 变、title_zh 不动、段落替换（请求序）", async () => {
    const { db, app, articleId } = await seedPendingArticle();
    const tok = await adminToken(app);
    const res = await app.request(`/api/admin/articles/${articleId}`, {
      method: "PUT",
      headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({
        title: "New Title",
        paragraphs: [
          { english_text: "E1", chinese_translation: "Z1" },
          { english_text: "E2", chinese_translation: "Z2" },
        ],
      }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: {} });

    const art = db.query("SELECT title_en, title_zh, paragraph_count FROM articles WHERE id = ?").get(articleId) as {
      title_en: string; title_zh: string; paragraph_count: number;
    };
    expect(art.title_en).toBe("New Title");
    expect(art.title_zh).toBe("题0"); // 不动
    expect(art.paragraph_count).toBe(2);
    const paras = db.query(
      "SELECT paragraph_index, text_en, text_zh FROM article_paragraphs WHERE article_id = ? ORDER BY paragraph_index",
    ).all(articleId) as { paragraph_index: number; text_en: string; text_zh: string }[];
    expect(paras).toEqual([
      { paragraph_index: 0, text_en: "E1", text_zh: "Z1" },
      { paragraph_index: 1, text_en: "E2", text_zh: "Z2" },
    ]);
    // 编辑后详情段落仍 1 起（0 基存储 + 响应 +1，与引擎段落一致）
    const detail = await (await app.request(`/api/admin/articles/${articleId}`, { headers: authHeader(tok) })).json();
    expect(detail.data.paragraphs).toEqual([
      { order_index: 1, english_text: "E1", chinese_translation: "Z1" },
      { order_index: 2, english_text: "E2", chinese_translation: "Z2" },
    ]);
  });

  test("编辑守卫：approved/rejected（非 pending_review）→ 404", async () => {
    const { db, app } = await buildApp();
    seedDay(db, [
      { slotIndex: 0, difficulty: "MEDIUM", status: "success" },
      { slotIndex: 1, difficulty: "MEDIUM", status: "success" },
    ]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(db);
    const slots = listSlots(db, RUN_DATE);
    approveArticle(db, slots[0]!.articleId!, "admin"); // approved
    db.query(
      "UPDATE article_review SET status = 'rejected', reject_reason = 'r', reviewed_by = 'admin' WHERE article_id = ?",
    ).run(slots[1]!.articleId!); // rejected（article_id UNIQUE：改既有行，非新插）
    const tok = await adminToken(app);
    const put = (id: number) =>
      app.request(`/api/admin/articles/${id}`, {
        method: "PUT",
        headers: { ...authHeader(tok), "content-type": "application/json" },
        body: JSON.stringify({ title: "x", paragraphs: [{ english_text: "a", chinese_translation: "b" }] }),
      });
    expect((await put(slots[0]!.articleId!)).status).toBe(404);
    expect((await put(slots[1]!.articleId!)).status).toBe(404);
  });

  test("编辑守卫：文章非槽位现指向（旧文）→ 404", async () => {
    const { db, app, articleId } = await seedPendingArticle();
    const slot = listSlots(db, RUN_DATE)[0]!;
    // 槽位换指新文后，旧文不再可编辑
    insertReplacementArticle(db, slot.id);
    const tok = await adminToken(app);
    const res = await app.request(`/api/admin/articles/${articleId}`, {
      method: "PUT",
      headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({ title: "x", paragraphs: [{ english_text: "a", chinese_translation: "b" }] }),
    });
    expect(res.status).toBe(404);
  });

  test("编辑校验：空 title / 空段落 / 段内 en-zh 双空 → 400 BAD_PARAM", async () => {
    const { db, app, articleId } = await seedPendingArticle();
    const tok = await adminToken(app);
    const put = (body: unknown) =>
      app.request(`/api/admin/articles/${articleId}`, {
        method: "PUT",
        headers: { ...authHeader(tok), "content-type": "application/json" },
        body: JSON.stringify(body),
      });
    const cases = [
      { title: "   ", paragraphs: [{ english_text: "a", chinese_translation: "b" }] },
      { title: "x", paragraphs: [] },
      { title: "x", paragraphs: [{ english_text: "", chinese_translation: "   " }] },
    ];
    for (const body of cases) {
      const res = await put(body);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect((await res.json()).error_code).toBe("BAD_PARAM");
    }
    // 校验失败零写入：title 未变
    const art = db.query("SELECT title_en FROM articles WHERE id = ?").get(articleId) as { title_en: string };
    expect(art.title_en).toBe("T0");
  });
});

describe("admin approve/reject/retry routes", () => {
  test("approve 路由直通：review → approved，reviewed_by = admin 用户名", async () => {
    const { db, app } = await buildApp();
    seedDay(db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "success" }]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(db);
    const articleId = listSlots(db, RUN_DATE)[0]!.articleId!;
    const tok = await adminToken(app);

    const res = await app.request(`/api/admin/articles/${articleId}/approve`, { method: "POST", headers: authHeader(tok) });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: {} });
    const r = db.query("SELECT status, reviewed_by FROM article_review WHERE article_id = ?").get(articleId) as {
      status: string; reviewed_by: string;
    };
    expect(r.status).toBe("approved");
    expect(r.reviewed_by).toBe("admin");
    // 重复 approve → 404
    expect((await app.request(`/api/admin/articles/${articleId}/approve`, { method: "POST", headers: authHeader(tok) })).status).toBe(404);
  });

  test("reject 路由直通（注入 gen）：拒绝→补生成（-r1），槽位回填新文", async () => {
    const { gen, calls } = successGen();
    const { db, app } = await buildApp({ gen });
    seedDay(db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "success" }]);
    const { ensureReviewRows } = await import("../src/services/review_service");
    ensureReviewRows(db);
    const slot = listSlots(db, RUN_DATE)[0]!;
    const oldId = slot.articleId!;
    const tok = await adminToken(app);

    const res = await app.request(`/api/admin/articles/${oldId}/reject`, {
      method: "POST",
      headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({ reason: "深度不足" }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: {} });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.threadId).toBe("daily-2026-09-02-0-r1");
    const oldReview = db.query("SELECT status, reject_reason, reviewed_by FROM article_review WHERE article_id = ?").get(oldId) as {
      status: string; reject_reason: string; reviewed_by: string;
    };
    expect(oldReview).toEqual({ status: "rejected", reject_reason: "深度不足", reviewed_by: "admin" });
    const s = db.query("SELECT article_id, status FROM batch_slots WHERE id = ?").get(slot.id) as {
      article_id: number; status: string;
    };
    expect(s.status).toBe("success");
    expect(s.article_id).not.toBe(oldId);
    const newReview = db.query("SELECT status FROM article_review WHERE article_id = ?").get(s.article_id) as { status: string };
    expect(newReview.status).toBe("pending_review");
  });

  test("slots retry 路由直通：error 槽重跑（唯一线程号）；槽位不存在 → 404", async () => {
    const { gen, calls } = successGen();
    const { db, app } = await buildApp({ gen });
    seedDay(db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "error" }]);
    const slot = listSlots(db, RUN_DATE)[0]!;
    const tok = await adminToken(app);

    const res = await app.request(`/api/admin/slots/${slot.id}/retry`, { method: "POST", headers: authHeader(tok) });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: {} });
    expect(calls).toHaveLength(1);
    expect(calls[0]!.threadId).toMatch(/^daily-2026-09-02-0-r\d+$/);
    const s = db.query("SELECT status, article_id FROM batch_slots WHERE id = ?").get(slot.id) as {
      status: string; article_id: number;
    };
    expect(s.status).toBe("success");
    expect(s.article_id).not.toBeNull();
    const rev = db.query("SELECT status FROM article_review WHERE article_id = ?").get(s.article_id) as { status: string };
    expect(rev.status).toBe("pending_review");

    const nf = await app.request("/api/admin/slots/999999/retry", { method: "POST", headers: authHeader(tok) });
    expect(nf.status).toBe(404);
  });

  test("slots retry 守卫：success/pending → 400（gen 不调用、槽位不动）；rejected/error → 200", async () => {
    const { gen, calls } = successGen();
    const { db, app } = await buildApp({ gen });
    seedDay(db, [
      { slotIndex: 0, difficulty: "MEDIUM", status: "success" },
      { slotIndex: 1, difficulty: "LOW", status: "pending" },
      { slotIndex: 2, difficulty: "MEDIUM", status: "rejected" },
      { slotIndex: 3, difficulty: "LOW", status: "error" },
    ]);
    const slots = listSlots(db, RUN_DATE);
    const tok = await adminToken(app);
    const retry = (id: number) =>
      app.request(`/api/admin/slots/${id}/retry`, { method: "POST", headers: authHeader(tok) });

    for (const idx of [0, 1]) {
      const res = await retry(slots[idx]!.id);
      expect(res.status, `slot ${idx}`).toBe(400);
      expect((await res.json()).error_code).toBe("BAD_PARAM");
    }
    for (const idx of [2, 3]) {
      expect((await retry(slots[idx]!.id)).status, `slot ${idx}`).toBe(200);
    }
    expect(calls).toHaveLength(2); // 仅 rejected/error 触发生成
    // success 槽未被改写：当前文章（可能已 approved）不下架
    const s = db.query("SELECT status, article_id FROM batch_slots WHERE id = ?").get(slots[0]!.id) as {
      status: string; article_id: number;
    };
    expect(s.status).toBe("success");
    expect(s.article_id).toBe(slots[0]!.articleId!);
  });
});

describe("admin articles generate", () => {
  test("非法日期 → 400 BAD_PARAM 且 genDaily 不调用", async () => {
    const genDailyCalls: { runDate: string; config?: AppConfig }[] = [];
    const genDaily: GenDailyFn = async (args) => {
      genDailyCalls.push(args);
      return { runDate: args.runDate, total: 0, results: [], summary: { success: 0, rejected: 0, error: 0 } };
    };
    const { app } = await buildApp({ genDaily });
    const tok = await adminToken(app);
    for (const date of ["2026-8-5", "2026-13-01", "abc", "2026-02-30"]) {
      const res = await app.request("/api/admin/articles/generate", {
        method: "POST",
        headers: { ...authHeader(tok), "content-type": "application/json" },
        body: JSON.stringify({ date }),
      });
      expect(res.status, date).toBe(400);
      expect((await res.json()).error_code).toBe("BAD_PARAM");
    }
    expect(genDailyCalls).toHaveLength(0);
  });

  test("合法日期 → genDaily 注入调用（runDate + config），随后 ensureReviewRows 补审核行", async () => {
    const genDailyCalls: { runDate: string; config?: AppConfig }[] = [];
    const genDaily: GenDailyFn = async (args) => {
      genDailyCalls.push(args);
      return { runDate: args.runDate, total: 0, results: [], summary: { success: 0, rejected: 0, error: 0 } };
    };
    const { db, app, engineCfg } = await buildApp({ genDaily });
    // 已有 success 槽位文章但无 review 行（模拟生成后未补审核）
    seedDay(db, [{ slotIndex: 0, difficulty: "MEDIUM", status: "success" }]);
    const articleId = listSlots(db, RUN_DATE)[0]!.articleId!;
    expect((db.query("SELECT COUNT(*) AS c FROM article_review").get() as { c: number }).c).toBe(0);
    const tok = await adminToken(app);

    const res = await app.request("/api/admin/articles/generate", {
      method: "POST",
      headers: { ...authHeader(tok), "content-type": "application/json" },
      body: JSON.stringify({ date: RUN_DATE }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: {} });
    expect(genDailyCalls).toEqual([{ runDate: RUN_DATE, config: engineCfg }]);
    // generate 后 ensureReviewRows：现有文章补 pending_review
    const r = db.query("SELECT status FROM article_review WHERE article_id = ?").get(articleId) as { status: string };
    expect(r.status).toBe("pending_review");
  });
});
