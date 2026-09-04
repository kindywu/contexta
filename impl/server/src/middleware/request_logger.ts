// src/middleware/request_logger.ts
// 请求访问日志中间件（挂主 app 首位，覆盖所有请求含匿名）：
// 记录 状态码/方法/路径+query/耗时/认证身份；按面分通道落文件——
// /admin 与 /api/admin/*（Web 管理端）→ accessLog("web")，其余（手机端）→ accessLog("app")；
// 身份来自 require_auth 写入的上下文（appUser / adminUser），未认证请求记 user=anon
// ——日志中间件自身不做认证、不读库。手机号打码，Authorization 头与请求体
// （token / 完整号码 / device_id）不落日志。异常路径同样记录后上抛，由顶层 onError 统一响应。
import type { Context, MiddlewareHandler } from "hono";
import { ApiError } from "../response";
import { accessLog, type AccessChannel } from "../services/server_log";
import type { ApiEnv } from "./require_auth";

/** 手机号打码（138****1035）：不足 7 位全掩；日志专用，不落完整号码。 */
function maskPhone(phone: string): string {
  if (phone.length < 7) return "*".repeat(phone.length);
  return `${phone.slice(0, 3)}****${phone.slice(-4)}`;
}

/** 认证身份（供日志显示）：App 用户打码手机号；管理员标 admin: 前缀；否则 anon。 */
function logUser(c: Context<ApiEnv>): string {
  const appUser = c.get("appUser");
  if (appUser) return maskPhone(appUser.phone);
  const adminUser = c.get("adminUser");
  if (adminUser) return `admin:${adminUser.username}`;
  return "anon";
}

/** 请求面 → 日志通道：/admin（页面/静态资源）与 /api/admin/*（管理端 API）为 Web 通道，其余为手机端。 */
function channelOf(pathname: string): AccessChannel {
  return pathname.startsWith("/admin") || pathname.startsWith("/api/admin/") ? "web" : "app";
}

export function requestLogger(): MiddlewareHandler<ApiEnv> {
  return async (c, next) => {
    const start = performance.now();
    const u = new URL(c.req.url);
    const channel = channelOf(u.pathname);
    try {
      await next();
      accessLog(
        channel,
        `${c.res.status} ${c.req.method} ${u.pathname}${u.search} user=${logUser(c)} ${Math.round(performance.now() - start)}ms`,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      accessLog(
        channel,
        `${status} ${c.req.method} ${u.pathname}${u.search} user=${logUser(c)} ${Math.round(performance.now() - start)}ms`,
      );
      throw err;
    }
  };
}
