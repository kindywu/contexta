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
  test("建齐 7 张表并可重复执行", () => {
    const db = freshDb();
    ensureServerSchema(db); // 幂等
    const tables = db.query("SELECT name FROM sqlite_master WHERE type='table'").all() as { name: string }[];
    const names = tables.map((t) => t.name);
    for (const t of ["users", "admin_user", "device_sessions", "usage_log", "word_lookup_cache", "article_review", "device_evictions"]) {
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

describe("server schema 自愈（多设备登录）", () => {
  test("旧结构库（无 device_name 列）跑 ensureServerSchema 后补列且幂等", () => {
    const old = new Database(":memory:");
    // 模拟本次变更前的 device_sessions 结构
    old.run(`CREATE TABLE device_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      phone TEXT NOT NULL,
      device_id TEXT NOT NULL,
      issued_at INTEGER NOT NULL,
      last_active_at INTEGER NOT NULL,
      UNIQUE(phone, device_id)
    )`);
    ensureServerSchema(old);
    const cols = old.query(`PRAGMA table_info(device_sessions)`).all() as { name: string }[];
    expect(cols.some((c) => c.name === "device_name")).toBe(true);
    // 幂等：重复执行不抛
    ensureServerSchema(old);
    const tables = old
      .query(`SELECT name FROM sqlite_master WHERE type='table'`)
      .all() as { name: string }[];
    expect(tables.some((t) => t.name === "device_evictions")).toBe(true);
    old.close();
  });

  test("device_evictions 列齐备", () => {
    const d = new Database(":memory:");
    ensureServerSchema(d);
    const cols = (d.query(`PRAGMA table_info(device_evictions)`).all() as { name: string }[])
      .map((c) => c.name);
    expect(cols).toEqual([
      "id", "phone", "device_id", "device_name", "reason", "ended_at",
      "by_device_id", "by_device_name", "by_issued_at", "created_at",
    ]);
    d.close();
  });
});
