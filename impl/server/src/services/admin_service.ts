import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { unauthorized } from "../response";
import { issueAdminToken } from "../jwt";
import { todayStartMillis } from "../time";

/** 用户列表行（wire 键名精确 snake_case；banned_reason/quota_word_daily 可空）。 */
export interface AdminUserRow {
  phone: string;
  status: string;
  banned_reason: string | null;
  created_at: number;
  quota_word_daily: number | null;
  today_word_lookups: number;
}

/** 用量汇总行（GROUP BY phone × endpoint；phone 可空 = 服务端任务侧独立成组）。 */
export interface UsageRow {
  phone: string | null;
  endpoint: string;
  calls: number;
  prompt_tokens: number;
  completion_tokens: number;
}

/** Task 8 前只含 login；其余端点（用户列表/封禁/配额/用量/文章审核……）后续增补。 */
export const adminService = {
  login(db: Database, cfg: ServerConfig, username: string, password: string): string {
    const row = db
      .query("SELECT password_hash FROM admin_user WHERE username = ?")
      .get(username) as { password_hash: string } | undefined;
    if (!row) throw unauthorized("TOKEN_EXPIRED");
    let valid = false;
    try {
      valid = Bun.password.verifySync(password, row.password_hash);
    } catch {
      valid = false;
    }
    if (!valid) throw unauthorized("TOKEN_EXPIRED");
    return issueAdminToken(cfg, username);
  },

  /**
   * 用户列表（按 created_at 升序）+ 每人今日查词次数：
   * usage_log word_lookup 行数（created_at >= 今日零点，与 llm_service 配额同一口径）。
   * quota_article_daily 为文章全局池预留列，不外露。
   */
  listUsers(db: Database, cfg: ServerConfig): AdminUserRow[] {
    const start = todayStartMillis(cfg.timeZone);
    const rows = db
      .query("SELECT phone, status, banned_reason, created_at, quota_word_daily FROM users ORDER BY created_at")
      .all() as { phone: string; status: string; banned_reason: string | null; created_at: number; quota_word_daily: number | null }[];
    return rows.map((r) => {
      const c = (
        db
          .query("SELECT COUNT(*) AS c FROM usage_log WHERE phone = ? AND endpoint = 'word_lookup' AND created_at >= ?")
          .get(r.phone, start) as { c: number }
      ).c;
      return {
        phone: r.phone,
        status: r.status,
        banned_reason: r.banned_reason,
        created_at: r.created_at,
        quota_word_daily: r.quota_word_daily,
        today_word_lookups: c,
      };
    });
  },

  /**
   * 封禁/解封：status 写 banned/normal，banned_reason 同步（解封置 NULL），updated_at 刷新。
   * phone 不存在时 UPDATE 0 行静默成功（对齐参考实现，未加 404 语义）。
   */
  setStatus(db: Database, phone: string, status: string, reason?: string | null): void {
    db.query("UPDATE users SET status = ?, banned_reason = ?, updated_at = ? WHERE phone = ?").run(
      status,
      reason ?? null,
      Date.now(),
      phone,
    );
  },

  /** 配额覆盖：quota_word_daily 置值（null = 清覆盖，回落全局默认），updated_at 刷新。 */
  setQuota(db: Database, phone: string, wordDaily?: number | null): void {
    db.query("UPDATE users SET quota_word_daily = ?, updated_at = ? WHERE phone = ?").run(
      wordDaily ?? null,
      Date.now(),
      phone,
    );
  },

  /** 今日用量汇总：按 (phone, endpoint) 聚合调用次数与 token 总量，created_at >= 今日零点。 */
  usageReport(db: Database, cfg: ServerConfig): UsageRow[] {
    const start = todayStartMillis(cfg.timeZone);
    return db
      .query(
        `SELECT phone, endpoint, COUNT(*) AS calls,
                SUM(prompt_tokens) AS prompt_tokens, SUM(completion_tokens) AS completion_tokens
         FROM usage_log WHERE created_at >= ?
         GROUP BY phone, endpoint ORDER BY phone, endpoint`,
      )
      .all(start) as UsageRow[];
  },
};
