// tests/llm_service.test.ts
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureSchema } from "../src/engine/db";
import { ensureServerSchema } from "../src/db";
import { llmService } from "../src/services/llm_service";
import { loadServerConfig } from "../src/config";

const cfg = loadServerConfig({ JWT_SECRET: "s".repeat(32), ADMIN_JWT_SECRET: "a".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" });

const goodChat = async () => ({
  content: `<spelling>apple</spelling><sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>苹果</chineseMeaning><englishDefinition>a fruit</englishDefinition></sense>`,
  promptTokens: 10,
  completionTokens: 5,
});

function freshDb(): Database {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  return db;
}

describe("llmService.wordLookup", () => {
  test("首次查询命中 LLM 并写入缓存，再次查询不调 LLM", async () => {
    const db = freshDb();
    let calls = 0;
    const chat = async () => { calls++; return goodChat(); };
    const r1 = await llmService.wordLookup(db, cfg, chat, "13800000000", "Apple");
    expect(r1.spelling).toBe("apple");
    const r2 = await llmService.wordLookup(db, cfg, chat, "13800000000", "apple");
    expect(r2.spelling).toBe("apple");
    expect(calls).toBe(1);
    expect((db.query("SELECT COUNT(*) as c FROM usage_log").get() as { c: number }).c).toBe(1);
  });
  test("配额超限 → QUOTA_EXCEEDED（全局默认）", async () => {
    const db = freshDb();
    const start = Date.now();
    db.run("INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES (?, 'word_lookup', 1, 1, 1, ?)", ["13900000000", start]);
    db.run("INSERT INTO users (phone, created_at, updated_at) VALUES ('13900000000', ?, ?)", [start, start]);
    await expect(llmService.wordLookup(db, { ...cfg, wordQuotaDaily: 1 }, goodChat, "13900000000", "dog"))
      .rejects.toMatchObject({ errorCode: "QUOTA_EXCEEDED" });
  });
  test("用户配额覆盖生效", async () => {
    const db = freshDb();
    const start = Date.now();
    db.run("INSERT INTO users (phone, quota_word_daily, created_at, updated_at) VALUES ('13700000000', 5, ?, ?)", [start, start]);
    db.run("INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES ('13700000000', 'word_lookup', 1, 1, 1, ?)", [start]);
    await llmService.wordLookup(db, { ...cfg, wordQuotaDaily: 1 }, goodChat, "13700000000", "cat");
    // 覆盖 5 ≥ 2 不超
  });
  test("空词 → 400 BAD_PARAM", async () => {
    const db = freshDb();
    await expect(llmService.wordLookup(db, cfg, goodChat, "13800000000", "  "))
      .rejects.toMatchObject({ errorCode: "BAD_PARAM" });
  });
  test("解析失败 → PIPELINE_BLOCKING", async () => {
    const db = freshDb();
    await expect(llmService.wordLookup(db, cfg, async () => ({ content: "garbage", promptTokens: 1, completionTokens: 1 }), "13800000000", "x"))
      .rejects.toMatchObject({ errorCode: "PIPELINE_BLOCKING" });
  });
  test("拼写不一致不入缓存", async () => {
    const db = freshDb();
    const chat = async () => ({ ...(await goodChat()), content: `<spelling>running</spelling><sense><partOfSpeech>v.</partOfSpeech><chineseMeaning>跑</chineseMeaning><englishDefinition>to move fast</englishDefinition></sense>` });
    await llmService.wordLookup(db, cfg, chat, "13800000000", "run");
    expect((db.query("SELECT COUNT(*) as c FROM word_lookup_cache").get() as { c: number }).c).toBe(0);
  });
  test("缓存形状不符（可解析但非 WordLookup）→ 删行自愈走 LLM", async () => {
    const db = freshDb();
    db.run("INSERT INTO word_lookup_cache (word, result_json, created_at) VALUES ('apple', '{\"foo\":\"bar\"}', ?)", [Date.now()]);
    let calls = 0;
    const chat = async () => { calls++; return goodChat(); };
    const r = await llmService.wordLookup(db, cfg, chat, "13800000000", "apple");
    expect(r.spelling).toBe("apple");
    expect(calls).toBe(1); // 形状不符缓存未命中，仍调 LLM
    const rows = db.query("SELECT result_json FROM word_lookup_cache WHERE word = 'apple'").all() as { result_json: string }[];
    expect(rows).toHaveLength(1); // 旧畸形行已删，新写好缓存
    expect((JSON.parse(rows[0].result_json) as { spelling: string }).spelling).toBe("apple");
  });
});
