import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdirSync, mkdtempSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { importPipelineData } from "../tool/import-data";

/**
 * 模拟真实旧 pipeline 库（4 表，articles 含 embedding 列——与
 * /Users/kindy/Documents/article-pipeline/data/pipeline.sqlite 同构，见 task-11-brief）。
 */
const PIPELINE_DDL = `
  CREATE TABLE article_batches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_date TEXT NOT NULL UNIQUE,
    total_slots INTEGER NOT NULL,
    completed_slots INTEGER NOT NULL DEFAULT 0,
    failed_slots INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'running'
      CHECK (status IN ('running', 'completed', 'completed_with_failures', 'failed')),
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    finished_at TEXT
  );
  CREATE TABLE articles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES article_batches(id),
    run_date TEXT NOT NULL,
    difficulty TEXT NOT NULL,
    category TEXT NOT NULL,
    path TEXT NOT NULL CHECK (path IN ('A', 'B')),
    source_url TEXT,
    title_en TEXT NOT NULL,
    title_zh TEXT NOT NULL,
    paragraph_count INTEGER NOT NULL,
    markdown_path TEXT NOT NULL,
    embedding BLOB NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    thread_id TEXT
  );
  CREATE INDEX idx_articles_source_url ON articles(source_url);
  CREATE INDEX idx_articles_created_at ON articles(created_at);
  CREATE INDEX idx_articles_batch_id ON articles(batch_id);
  CREATE TABLE article_paragraphs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER NOT NULL REFERENCES articles(id),
    paragraph_index INTEGER NOT NULL,
    text_en TEXT NOT NULL,
    text_zh TEXT NOT NULL,
    UNIQUE(article_id, paragraph_index)
  );
  CREATE TABLE batch_slots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER NOT NULL REFERENCES article_batches(id),
    run_date TEXT NOT NULL,
    slot_index INTEGER NOT NULL,
    difficulty TEXT NOT NULL,
    thread_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending','success','rejected','error')),
    attempts INTEGER NOT NULL DEFAULT 1,
    article_id INTEGER REFERENCES articles(id),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(batch_id, slot_index)
  );
  CREATE INDEX idx_batch_slots_run_date ON batch_slots(run_date);
`;

const INSERT_ARTICLE = `
  INSERT INTO articles (id, batch_id, run_date, difficulty, category, path, source_url,
    title_en, title_zh, paragraph_count, markdown_path, embedding, thread_id)
  VALUES (?, 1, '2026-09-01', 'LOW', 'daily_conversation', 'B', ?, ?, ?, ?, ?, X'0102', ?)
`;

/**
 * 构造源库副本：WAL 模式（真实源为 wal，close 后残留 -wal/-shm 侧车）；
 * 1 批次 / 3 槽（slot 0、1 success→a1、a2；slot 2 error 无文章）/ 2 篇文章（各 2 段）。
 * tamper=true 时 a2 的 paragraph_count=5（实际 2 段）——段落校验必须失败。
 */
function buildSource(path: string, opts: { tamper?: boolean } = {}): void {
  const db = new Database(path);
  db.exec("PRAGMA journal_mode = WAL");
  db.exec(PIPELINE_DDL);
  db.run("INSERT INTO article_batches (run_date, total_slots, status) VALUES ('2026-09-01', 3, 'completed_with_failures')");
  const insSlot = db.query(
    "INSERT INTO batch_slots (batch_id, run_date, slot_index, difficulty, thread_id, status, attempts, article_id) VALUES (1, '2026-09-01', ?, 'LOW', ?, ?, 1, ?)",
  );
  insSlot.run(0, "daily-2026-09-01-0", "success", 1);
  insSlot.run(1, "daily-2026-09-01-1", "success", 2);
  insSlot.run(2, "daily-2026-09-01-2", "error", null);
  const insArticle = db.query(INSERT_ARTICLE);
  const insPara = db.query("INSERT INTO article_paragraphs (article_id, paragraph_index, text_en, text_zh) VALUES (?, ?, ?, ?)");
  for (const [id, en, zh, count] of [
    [1, "Hello day", "你好", 2],
    [2, "Second day", "第二天", opts.tamper ? 5 : 2],
  ] as [number, string, string, number][]) {
    insArticle.run(id, `https://example.com/${id}.html`, en, zh, count, `out/a${id}.md`, `daily-2026-09-01-${id - 1}`);
    for (let i = 0; i < 2; i++) {
      insPara.run(id, i, `${en} p${i}`, `${zh} p${i}`);
    }
  }
  db.exec("PRAGMA wal_checkpoint(TRUNCATE)"); // 主文件完整落盘；-wal/-shm 仍残留（模拟真实源）
  db.close();
}

/** 模拟已存在的旧 target（WAL 模式 + marker 表 + close 残留侧车）→ 触发 target 备份与残留 -wal 路径。 */
function buildOldTarget(path: string): void {
  const db = new Database(path);
  db.exec("PRAGMA journal_mode = WAL");
  db.exec("CREATE TABLE garbage (x INTEGER)");
  db.run("INSERT INTO garbage VALUES (42)");
  db.close(); // 不 checkpoint：marker 行可能只在 -wal 里——备份必须一并拷侧车才完整
}

function countRows(db: Database, sql: string): number {
  return (db.query(sql).get() as { c: number }).c;
}

describe("importPipelineData", () => {
  test("导入成功：备份（含源副作用车与旧 target）→ 去 embedding 重建 → 历史 approved → 校验通过", async () => {
    const dir = mkdtempSync(join(tmpdir(), "contexta-import-"));
    const source = join(dir, "pipeline.sqlite");
    const target = join(dir, "data", "contexta.db");
    const backup = join(dir, ".backup");
    buildSource(source);
    mkdirSync(join(dir, "data"), { recursive: true });
    buildOldTarget(target); // 旧 target 已存在 → 应备份为 target-<ts>.sqlite（含侧车）

    const report = await importPipelineData(source, target, backup);
    expect(report).toEqual({ batches: 1, articles: 2, reviewRows: 2, nonSuccessSlots: 1, integrity: "ok" });

    const db = new Database(target, { readonly: true });
    try {
      // 1. 重建后无 embedding 列，保留 thread_id
      const cols = (db.query("SELECT name FROM pragma_table_info('articles')").all() as { name: string }[]).map(
        (c) => c.name,
      );
      expect(cols).toContain("thread_id");
      expect(cols).not.toContain("embedding");
      // 2. 行数保留（含 id）
      expect(countRows(db, "SELECT count(*) AS c FROM articles")).toBe(2);
      expect((db.query("SELECT id FROM articles ORDER BY id").all() as { id: number }[]).map((r) => r.id)).toEqual([1, 2]);
      // 3. 历史审核行：= success 槽文章数，status=approved、reviewed_by=import
      const reviews = db
        .query("SELECT article_id, slot_id, status, reviewed_by FROM article_review ORDER BY article_id")
        .all();
      expect(reviews).toEqual([
        { article_id: 1, slot_id: 1, status: "approved", reviewed_by: "import" },
        { article_id: 2, slot_id: 2, status: "approved", reviewed_by: "import" },
      ]);
      // 4. 段落原样保留；槽位状态原样保留
      expect(countRows(db, "SELECT count(*) AS c FROM article_paragraphs")).toBe(4);
      expect(countRows(db, "SELECT count(*) AS c FROM batch_slots WHERE status != 'success'")).toBe(1);
      // 5. 旧 target 内容被整体替换（残留 -wal 没有被合并进来）
      expect(db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='garbage'").get()).toBeNull();
    } finally {
      db.close();
    }

    // 6. 备份目录：源主文件 + 源 -wal/-shm 侧车 + 旧 target 主文件
    const files = readdirSync(backup);
    expect(files.some((f) => /^pipeline-source-\d{8}-\d{6}\.sqlite$/.test(f))).toBe(true);
    expect(files.some((f) => /^pipeline-source-.*\.sqlite-wal$/.test(f))).toBe(true);
    expect(files.some((f) => /^pipeline-source-.*\.sqlite-shm$/.test(f))).toBe(true);
    const targetBackup = files.find((f) => /^target-\d{8}-\d{6}\.sqlite$/.test(f));
    expect(targetBackup).toBeDefined();
    // 7. 旧 target 备份可完整恢复（marker 行可能在 -wal 里——拷了侧车才能读到）
    const old = new Database(join(backup, targetBackup!), { readonly: true });
    try {
      expect(countRows(old, "SELECT count(*) AS c FROM garbage")).toBe(1);
    } finally {
      old.close();
    }
  });

  test("篡改段落数（paragraph_count ≠ 实际段数）→ 抛错，源库不动", async () => {
    const dir = mkdtempSync(join(tmpdir(), "contexta-import-"));
    const source = join(dir, "pipeline.sqlite");
    const target = join(dir, "data", "contexta.db");
    const backup = join(dir, ".backup");
    buildSource(source, { tamper: true }); // a2: paragraph_count=5，实为 2 段

    await expect(importPipelineData(source, target, backup)).rejects.toThrow(/段落/);

    // 源库未被修改：embedding 列仍在、行数与原值不变
    const s = new Database(source, { readonly: true });
    try {
      const cols = (s.query("SELECT name FROM pragma_table_info('articles')").all() as { name: string }[]).map(
        (c) => c.name,
      );
      expect(cols).toContain("embedding");
      expect(countRows(s, "SELECT count(*) AS c FROM articles")).toBe(2);
      expect((s.query("SELECT paragraph_count FROM articles WHERE id = 2").get() as { paragraph_count: number }).paragraph_count).toBe(5);
    } finally {
      s.close();
    }
    // 备份在抛错前已完成；本次 target 原本不存在 → 无 target 备份
    const files = readdirSync(backup);
    expect(files.some((f) => f.startsWith("pipeline-source-"))).toBe(true);
    expect(files.some((f) => f.startsWith("target-"))).toBe(false);
  });
});
