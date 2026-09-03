import type { Database } from "bun:sqlite";

/**
 * 服务端表（对齐旧 001-init.sql，时间戳 Unix millis INTEGER）。
 * 与引擎 4 表共用同一库：调用方先 `ensureSchema(db)`（引擎），再 `ensureServerSchema(db)`。
 * article_review 的 article_id/slot_id 引用由引擎 ensureSchema 创建的 articles(id)/batch_slots(id)。
 * article_delivery（2026-09-03 文章投放）：账户×文章的交付账本；UNIQUE(phone, article_id)——同一 phone 号（含重装换 device_id / 多设备）永不重复投同一篇（学习者是"人"，不读相同文章）；device_id 仅记录交付设备，不参与冻结/游标/已读逻辑（均按 phone×难度）。
 */
const SERVER_DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS users (
    phone TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'normal',
    banned_reason TEXT,
    quota_word_daily INTEGER,
    quota_article_daily INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS admin_user (
    username TEXT PRIMARY KEY,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS device_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL,
    device_id TEXT NOT NULL,
    issued_at INTEGER NOT NULL,
    last_active_at INTEGER NOT NULL,
    UNIQUE(phone, device_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_device_sessions_phone ON device_sessions(phone)`,
  `CREATE TABLE IF NOT EXISTS usage_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT,
    endpoint TEXT NOT NULL,
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    latency_ms INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_usage_phone_created ON usage_log(phone, created_at)`,
  `CREATE INDEX IF NOT EXISTS idx_usage_created ON usage_log(created_at)`,
  `CREATE TABLE IF NOT EXISTS word_lookup_cache (
    word TEXT PRIMARY KEY,
    result_json TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS article_review (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER NOT NULL UNIQUE REFERENCES articles(id),
    slot_id INTEGER NOT NULL REFERENCES batch_slots(id),
    status TEXT NOT NULL DEFAULT 'pending_review'
        CHECK (status IN ('pending_review','approved','rejected','rejected_final')),
    reject_reason TEXT,
    reviewed_by TEXT,
    reviewed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`,
  `CREATE INDEX IF NOT EXISTS idx_article_review_slot ON article_review(slot_id)`,
  `CREATE TABLE IF NOT EXISTS article_delivery (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phone TEXT NOT NULL,
    device_id TEXT NOT NULL,
    difficulty TEXT NOT NULL,
    article_id INTEGER NOT NULL REFERENCES articles(id),
    delivery_date TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE(phone, article_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_article_delivery_client_date
    ON article_delivery(phone, difficulty, delivery_date)`,
];

/** 幂等建服务端表：逐条 run（CREATE TABLE / INDEX 均 IF NOT EXISTS）。 */
export function ensureServerSchema(db: Database): void {
  for (const stmt of SERVER_DDL) {
    db.run(stmt);
  }
}

/**
 * 无该 username 行才插入 admin（argon2id 哈希）；返回是否新插。
 * 重复调用返回 false 且不覆盖既有密码。
 */
export async function seedAdminIfNeeded(
  db: Database,
  username: string,
  password: string,
): Promise<boolean> {
  const exists = db.query("SELECT 1 FROM admin_user WHERE username = ?").get(username);
  if (exists) return false;
  const hash = await Bun.password.hash(password, { algorithm: "argon2id" });
  const now = Date.now();
  db.query(
    "INSERT INTO admin_user (username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?)",
  ).run(username, hash, now, now);
  return true;
}

/**
 * 校验 admin 密码（argon2id verify）；行不存在或 verify 抛错 → false。
 * 用 verifySync 保持同步 boolean 签名（与 brief 测试的同步调用一致）。
 */
export function verifyAdminPassword(db: Database, username: string, password: string): boolean {
  const row = db
    .query("SELECT password_hash FROM admin_user WHERE username = ?")
    .get(username) as { password_hash: string } | undefined;
  if (!row) return false;
  try {
    return Bun.password.verifySync(password, row.password_hash);
  } catch {
    return false;
  }
}
