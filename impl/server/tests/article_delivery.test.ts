// tests/article_delivery.test.ts
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureServerSchema } from "../src/db";
import { ensureSchema } from "../src/engine/db";

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
