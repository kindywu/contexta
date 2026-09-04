// src/middleware/require_auth.ts
// 登录保护中间件：认证成功把用户写入请求上下文（appUser / adminUser），
// 处理器经 c.get("appUser") 读取，不再各自解析 Authorization 头。
// 认证失败抛原 ApiError（缺失/过期 token → 401 TOKEN_EXPIRED、被顶号 → 401 EVICTED、
// 封禁 → 403 BANNED），由路由 attachErrorHandler / 顶层 onError 统一响应。
import type { MiddlewareHandler } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { resolveAdminAuth, resolveAuthUser, type AuthUser } from "../auth";

/** 认证结果挂入请求上下文（c.set/get）的变量键。 */
export interface ApiVariables {
  appUser?: AuthUser;
  adminUser?: { username: string };
}
export type ApiEnv = { Variables: ApiVariables };

/**
 * App 登录保护：拦截所有需要登录的 /api/* 请求（挂在各路由工厂内，
 * 直连 router 的测试同样生效）。探测未认证/过期/封禁的语义由 resolveAuthUser 决定。
 */
export function requireAppAuth(db: Database, cfg: ServerConfig): MiddlewareHandler<ApiEnv> {
  return async (c, next) => {
    c.set("appUser", resolveAuthUser(db, cfg, c.req.header("authorization")));
    await next();
  };
}

/**
 * Admin 登录保护：拦截 /api/admin/*（POST /api/admin/login 公开放行，登录换取 token 本身
 * 不能要求已认证；错误凭据由 adminService.login 抛 401 INVALID_CREDENTIALS）。
 */
export function requireAdminAuth(db: Database, cfg: ServerConfig): MiddlewareHandler<ApiEnv> {
  return async (c, next) => {
    if (c.req.path === "/api/admin/login" && c.req.method === "POST") return next();
    c.set("adminUser", resolveAdminAuth(db, cfg, c.req.header("authorization")));
    await next();
  };
}
