import type { Database } from "bun:sqlite";
import type { ServerConfig } from "./config";
import { banned, unauthorized } from "./response";
import { verifyAppToken, verifyAdminToken, type AppClaims, type AdminClaims } from "./jwt";
import { authService } from "./services/auth_service";

export interface AuthUser {
  phone: string;
  deviceId: string;
}

/**
 * App 认证提取器（对齐旧版 extractors.rs AuthUser）：
 * 缺头/无效 token → 401 TOKEN_EXPIRED；先封禁后会话（被封禁得 403 BANNED）；
 * 会话行 issued_at 必须与 token 的 iat 毫秒级精确相等，否则 401 EVICTED。
 */
export function resolveAuthUser(
  db: Database,
  cfg: ServerConfig,
  header: string | undefined,
): AuthUser {
  const token = header?.startsWith("Bearer ") ? header.slice(7) : undefined;
  if (!token) throw unauthorized("TOKEN_EXPIRED");
  let claims: AppClaims;
  try {
    claims = verifyAppToken(cfg, token);
  } catch {
    throw unauthorized("TOKEN_EXPIRED");
  }
  if (authService.isBanned(db, claims.sub)) throw banned("account banned");
  const issuedAt = authService.sessionIssuedAt(db, claims.sub, claims.device_id);
  if (issuedAt !== claims.iat) throw unauthorized("EVICTED");
  return { phone: claims.sub, deviceId: claims.device_id };
}

/** Admin 认证提取器（对齐旧版 extractors.rs AdminAuth）：role != admin → 401 TOKEN_EXPIRED。 */
export function resolveAdminAuth(
  db: Database,
  cfg: ServerConfig,
  header: string | undefined,
): { username: string } {
  const token = header?.startsWith("Bearer ") ? header.slice(7) : undefined;
  if (!token) throw unauthorized("TOKEN_EXPIRED");
  let claims: AdminClaims;
  try {
    claims = verifyAdminToken(cfg, token);
  } catch {
    throw unauthorized("TOKEN_EXPIRED");
  }
  if (claims.role !== "admin") throw unauthorized("TOKEN_EXPIRED");
  return { username: claims.sub };
}
