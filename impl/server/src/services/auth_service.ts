import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { banned } from "../response";
import { issueAppToken } from "../jwt";

const MAX_ACTIVE_DEVICES = 2;

/**
 * 登录事务语义与旧版 auth_service.rs 完全一致：
 * 1. users 自动注册（ON CONFLICT DO NOTHING）；
 * 2. 封禁检查先于会话（被封禁账号 login 也得 403 BANNED）；
 * 3. issued_at 按 phone 全局单调——插入与重登都取「全局 MAX(issued_at) + 1」（与墙钟
 *    取大，防时钟回拨），单条 INSERT...SELECT 在 SQLite 写锁内原子求 MAX，无事务竞态；
 * 4. 挤掉：保留按 issued_at 最新 2 条（id DESC 仅作永不到达的兜底）；
 * 5. token 的 iat 取会话行实际落库的 issued_at，保证重登即令旧 token 失效（I2）。
 */
export const authService = {
  login(db: Database, cfg: ServerConfig, phone: string, deviceId: string): string {
    const now = Date.now();
    db.query(
      "INSERT INTO users (phone, status, created_at, updated_at) VALUES (?, 'normal', ?, ?) ON CONFLICT(phone) DO NOTHING",
    ).run(phone, now, now);
    if (authService.isBanned(db, phone)) throw banned("account banned");
    db.query(
      `INSERT INTO device_sessions (phone, device_id, issued_at, last_active_at)
       SELECT ?, ?, max(COALESCE(MAX(issued_at), 0) + 1, ?), ?
       FROM device_sessions WHERE phone = ?
       ON CONFLICT(phone, device_id) DO UPDATE SET
         issued_at = excluded.issued_at, last_active_at = excluded.last_active_at`,
    ).run(phone, deviceId, now, now, phone);
    // 挤掉：保留按 issued_at 最新的 2 条（含刚插入/刚更新的）。
    db.query(
      `DELETE FROM device_sessions WHERE phone = ? AND id NOT IN (
         SELECT id FROM device_sessions WHERE phone = ? ORDER BY issued_at DESC, id DESC LIMIT ${MAX_ACTIVE_DEVICES})`,
    ).run(phone, phone);
    const row = db
      .query("SELECT issued_at FROM device_sessions WHERE phone = ? AND device_id = ?")
      .get(phone, deviceId) as { issued_at: number };
    return issueAppToken(cfg, phone, deviceId, row.issued_at);
  },

  logout(db: Database, phone: string, deviceId: string): void {
    db.query("DELETE FROM device_sessions WHERE phone = ? AND device_id = ?").run(phone, deviceId);
  },

  /** 会话行的 issued_at（毫秒，签发时刻）；undefined = 无会话（登出/被挤掉）。 */
  sessionIssuedAt(db: Database, phone: string, deviceId: string): number | undefined {
    const row = db
      .query("SELECT issued_at FROM device_sessions WHERE phone = ? AND device_id = ?")
      .get(phone, deviceId) as { issued_at: number } | undefined;
    return row?.issued_at;
  },

  isBanned(db: Database, phone: string): boolean {
    const row = db.query("SELECT status FROM users WHERE phone = ?").get(phone) as
      | { status: string }
      | undefined;
    return row?.status === "banned";
  },
};
