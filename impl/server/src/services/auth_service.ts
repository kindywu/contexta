import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { banned } from "../response";
import { issueAppToken } from "../jwt";

const MAX_ACTIVE_DEVICES = 2;

/** 会话设备信息（预览与登录响应的 evicted 列表共用）。 */
export interface SessionDeviceInfo {
  device_id: string;
  device_name: string | null;
  issued_at: number;
  last_active_at: number;
}

/** 401 EVICTED 的 detail：谁在何时结束了本设备的会话。 */
export interface EvictionDetail {
  reason: "evicted" | "relogin";
  ended_at: number;
  by: { device_id: string; device_name: string | null; issued_at: number };
}

interface SessionRow {
  id: number;
  device_id: string;
  device_name: string | null;
  issued_at: number;
  last_active_at: number;
}

function listSessions(db: Database, phone: string): SessionRow[] {
  return db
    .query(
      `SELECT id, device_id, device_name, issued_at, last_active_at
       FROM device_sessions WHERE phone = ?`,
    )
    .all(phone) as SessionRow[];
}

/**
 * 挤掉判定（预览与登录共用同一规则，避免漂移）：
 * 本机以 `issuedAt` 参与排序，按 (issued_at DESC, id DESC) 保留最新 2 条，其余为被挤。
 * issued_at 按 phone 全局单调，故 id 仅作兜底（本机占位 id 用 0，不会参与决胜）。
 */
function pickEvicted(rows: SessionRow[], deviceId: string, issuedAt: number): SessionRow[] {
  const merged: SessionRow[] = [
    ...rows.filter((r) => r.device_id !== deviceId),
    { id: 0, device_id: deviceId, device_name: null, issued_at: issuedAt, last_active_at: issuedAt },
  ];
  merged.sort((a, b) => b.issued_at - a.issued_at || b.id - a.id);
  return merged.slice(MAX_ACTIVE_DEVICES);
}

function toInfo(row: SessionRow): SessionDeviceInfo {
  return {
    device_id: row.device_id,
    device_name: row.device_name,
    issued_at: row.issued_at,
    last_active_at: row.last_active_at,
  };
}

function writeEviction(
  db: Database,
  v: {
    phone: string;
    deviceId: string;
    deviceName: string | null;
    reason: "evicted" | "relogin";
    endedAt: number;
    byDeviceId: string;
    byDeviceName: string | null;
    byIssuedAt: number;
  },
): void {
  db.query(
    `INSERT INTO device_evictions
       (phone, device_id, device_name, reason, ended_at, by_device_id, by_device_name, by_issued_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    v.phone, v.deviceId, v.deviceName, v.reason, v.endedAt,
    v.byDeviceId, v.byDeviceName, v.byIssuedAt, Date.now(),
  );
}

/**
 * 登录事务语义与旧版一致（users 自动注册 → 封禁检查 → issued_at 全局单调 → 保留最新 2 条），
 * 2026-09-18 扩展：
 * - 登录时记录 device_name（机型名，客户端上报；旧版本缺省不覆盖已有值）；
 * - 被挤掉的会话行写 device_evictions（reason='evicted'）；
 * - 同设备重登（旧 token 因 iat 落后失效）写 device_evictions（reason='relogin'）；
 * - 返回 { token, evicted }（evicted = 本次实际被删除的会话）。
 */
export const authService = {
  login(
    db: Database,
    cfg: ServerConfig,
    phone: string,
    deviceId: string,
    deviceName?: string,
  ): { token: string; evicted: SessionDeviceInfo[] } {
    const now = Date.now();
    db.query(
      "INSERT INTO users (phone, status, created_at, updated_at) VALUES (?, 'normal', ?, ?) ON CONFLICT(phone) DO NOTHING",
    ).run(phone, now, now);
    if (authService.isBanned(db, phone)) throw banned("account banned");

    const before = listSessions(db, phone);
    const previous = before.find((r) => r.device_id === deviceId);
    const maxIssued = before.reduce((m, r) => Math.max(m, r.issued_at), 0);
    const issuedAt = Math.max(maxIssued + 1, now);

    db.query(
      `INSERT INTO device_sessions (phone, device_id, device_name, issued_at, last_active_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(phone, device_id) DO UPDATE SET
         device_name = COALESCE(excluded.device_name, device_sessions.device_name),
         issued_at = excluded.issued_at,
         last_active_at = excluded.last_active_at`,
    ).run(phone, deviceId, deviceName ?? null, issuedAt, now);

    const after = listSessions(db, phone);
    const evicted = pickEvicted(after, deviceId, issuedAt);

    if (previous) {
      writeEviction(db, {
        phone,
        deviceId,
        deviceName: previous.device_name,
        reason: "relogin",
        endedAt: now,
        byDeviceId: deviceId,
        byDeviceName: deviceName ?? previous.device_name,
        byIssuedAt: issuedAt,
      });
    }
    for (const v of evicted) {
      writeEviction(db, {
        phone,
        deviceId: v.device_id,
        deviceName: v.device_name,
        reason: "evicted",
        endedAt: now,
        byDeviceId: deviceId,
        byDeviceName: deviceName ?? null,
        byIssuedAt: issuedAt,
      });
    }

    db.query(
      `DELETE FROM device_sessions WHERE phone = ? AND id NOT IN (
         SELECT id FROM device_sessions WHERE phone = ? ORDER BY issued_at DESC, id DESC LIMIT ${MAX_ACTIVE_DEVICES})`,
    ).run(phone, phone);

    const row = db
      .query("SELECT issued_at FROM device_sessions WHERE phone = ? AND device_id = ?")
      .get(phone, deviceId) as { issued_at: number };
    return { token: issueAppToken(cfg, phone, deviceId, row.issued_at), evicted: evicted.map(toInfo) };
  },

  /** 登录预览（纯模拟不落库）：此刻登录会被挤掉的设备（0/1 条）。 */
  previewEvictions(db: Database, phone: string, deviceId: string): SessionDeviceInfo[] {
    const rows = listSessions(db, phone);
    const maxIssued = rows.reduce((m, r) => Math.max(m, r.issued_at), 0);
    const issuedAt = Math.max(maxIssued + 1, Date.now());
    return pickEvicted(rows, deviceId, issuedAt).map(toInfo);
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

  /** 401 EVICTED 详情：该 token 签发之后最近一次会话结束事件（无记录 → undefined）。 */
  evictionDetail(
    db: Database,
    phone: string,
    deviceId: string,
    sinceIssuedAt: number,
  ): EvictionDetail | undefined {
    const row = db
      .query(
        `SELECT reason, ended_at, by_device_id, by_device_name, by_issued_at
         FROM device_evictions
         WHERE phone = ? AND device_id = ? AND ended_at > ?
         ORDER BY id DESC LIMIT 1`,
      )
      .get(phone, deviceId, sinceIssuedAt) as
      | { reason: "evicted" | "relogin"; ended_at: number; by_device_id: string; by_device_name: string | null; by_issued_at: number }
      | undefined;
    if (!row) return undefined;
    return {
      reason: row.reason,
      ended_at: row.ended_at,
      by: { device_id: row.by_device_id, device_name: row.by_device_name, issued_at: row.by_issued_at },
    };
  },

  isBanned(db: Database, phone: string): boolean {
    const row = db.query("SELECT status FROM users WHERE phone = ?").get(phone) as
      | { status: string }
      | undefined;
    return row?.status === "banned";
  },
};
