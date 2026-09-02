import type { Hono } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export class ApiError extends Error {
  constructor(
    public readonly status: number,   // HTTP 状态码
    public readonly code: number,     // body.code
    public readonly errorCode: string,
    message: string,
  ) {
    super(message);
  }
}

export function ok<T>(data: T): { code: 0; data: T } {
  return { code: 0, data };
}

export function badRequest(message: string, errorCode = "BAD_PARAM"): ApiError {
  return new ApiError(400, 400, errorCode, message);
}
export function quotaExceeded(message: string): ApiError {
  return new ApiError(400, 40001, "QUOTA_EXCEEDED", message);
}
export function unauthorized(errorCode: string): ApiError {
  return new ApiError(401, 401, errorCode, "unauthorized");
}
export function banned(message: string): ApiError {
  return new ApiError(403, 403, "BANNED", message);
}
export function notFound(message: string): ApiError {
  return new ApiError(404, 404, "NOT_FOUND", message);
}
export function llmFatal(message: string): ApiError {
  return new ApiError(500, 500, "LLM_FATAL", message);
}
export function llmRecoverableExhausted(message: string): ApiError {
  return new ApiError(502, 502, "LLM_RECOVERABLE_EXHAUSTED", message);
}
export function llmTimeout(message: string): ApiError {
  return new ApiError(504, 504, "LLM_TIMEOUT", message);
}
export function pipelineBlocking(message: string): ApiError {
  return new ApiError(500, 500, "PIPELINE_BLOCKING", message);
}
export function internal(err: unknown): ApiError {
  console.error("internal error:", err);
  return new ApiError(500, 500, "INTERNAL", "internal error");
}

export function errorBody(e: ApiError): { code: number; message: string; error_code: string } {
  return { code: e.code, message: e.message, error_code: e.errorCode };
}

/**
 * 给 Hono app 挂统一错误处理：handler 内 throw ApiError → 对应 status + errorBody；
 * SyntaxError（畸形 JSON body，c.req.json 抛出）→ 400 BAD_PARAM；
 * 其余异常 → 500 INTERNAL。路由工厂（authRouter/adminRouter 等）创建后立即挂载，
 * 子路由经 `app.route()` 挂载时 Hono 会组合子 app 的 errorHandler，嵌套仍生效——
 * 子路由内错误就地消化不上抛顶层（顶层 onError 只兜 main 侧代码）。
 */
export function attachErrorHandler(app: Hono): void {
  app.onError((err, c) => {
    if (err instanceof SyntaxError) {
      return c.json(errorBody(badRequest("invalid JSON body")), 400);
    }
    if (err instanceof ApiError) {
      return c.json(errorBody(err), err.status as ContentfulStatusCode);
    }
    console.error("internal error:", err);
    return c.json(errorBody(new ApiError(500, 500, "INTERNAL", "internal error")), 500);
  });
}
