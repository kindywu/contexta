// tests/db.test.ts
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureServerSchema, seedAdminIfNeeded, verifyAdminPassword } from "../src/db";
import { ensureSchema } from "../src/engine/db";

function freshDb(): Database {
  const db = new Database(":memory:");
  ensureSchema(db);        // 引擎 4 表
  ensureServerSchema(db);  // 服务端表
  return db;
}

describe("ensureServerSchema", () => {
  test("建齐 6 张表并可重复执行", () => {
    const db = freshDb();
    ensureServerSchema(db); // 幂等
    const tables = db.query("SELECT name FROM sqlite_master WHERE type='table'").all() as { name: string }[];
    const names = tables.map((t) => t.name);
    for (const t of ["users", "admin_user", "device_sessions", "usage_log", "word_lookup_cache", "article_review"]) {
      expect(names).toContain(t);
    }
  });
  test("article_review CHECK 约束生效", () => {
    const db = freshDb();
    expect(() =>
      db.run("INSERT INTO article_review (article_id, slot_id, status) VALUES (1, 1, 'bogus')"),
    ).toThrow();
  });
});

describe("seedAdminIfNeeded / verifyAdminPassword", () => {
  test("首次 seed 建立 admin，重复 seed 不覆盖", async () => {
    const db = freshDb();
    expect(await seedAdminIfNeeded(db, "admin", "pw-123456")).toBe(true);
    expect(await seedAdminIfNeeded(db, "admin", "other-pw")).toBe(false);
    expect(verifyAdminPassword(db, "admin", "pw-123456")).toBe(true);
    expect(verifyAdminPassword(db, "admin", "other-pw")).toBe(false);
  });
  test("未知用户返回 false", () => {
    const db = freshDb();
    expect(verifyAdminPassword(db, "nobody", "x")).toBe(false);
  });
});
