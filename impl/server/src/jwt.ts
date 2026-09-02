import jwt from "jsonwebtoken";
import type { ServerConfig } from "./config";

export const APP_TOKEN_TTL_SECS = 30 * 24 * 3600;
export const ADMIN_TOKEN_TTL_SECS = 12 * 3600;

export interface AppClaims {
  sub: string; // phone
  device_id: string;
  // I2（审查）：签发时刻（毫秒），与会话行 device_sessions.issued_at 精确一致。
  // JWT 惯例 iat 用秒，但重登校验要求 `claims.iat == issued_at` 精确相等——
  // 秒粒度无法区分同秒内的两次重登，故用毫秒对齐（jsonwebtoken 原样透传，无舍入）。
  iat: number;
  exp: number;
}

export interface AdminClaims {
  sub: string; // username
  role: string;
  exp: number;
}

export function issueAppToken(
  cfg: ServerConfig,
  phone: string,
  deviceId: string,
  issuedAtMs: number,
): string {
  const claims: AppClaims = {
    sub: phone,
    device_id: deviceId,
    iat: issuedAtMs,
    exp: Math.floor(Date.now() / 1000) + APP_TOKEN_TTL_SECS,
  };
  return jwt.sign(claims, cfg.jwtSecret, { header: { alg: "HS256" } });
}

export function issueAdminToken(cfg: ServerConfig, username: string): string {
  const claims: AdminClaims = {
    sub: username,
    role: "admin",
    exp: Math.floor(Date.now() / 1000) + ADMIN_TOKEN_TTL_SECS,
  };
  return jwt.sign(claims, cfg.jwtSecret, { header: { alg: "HS256" } });
}

export function verifyToken<T>(cfg: ServerConfig, token: string): T {
  return jwt.verify(token, cfg.jwtSecret) as T;
}
