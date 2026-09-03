// src/routers/health.ts
// 健康检查：GET /api/health → ok({ status: "ok" })。无鉴权（探活端点）。
import { Hono } from "hono";
import { attachErrorHandler, ok } from "../response";

export function healthRouter(): Hono {
  const app = new Hono();
  attachErrorHandler(app);

  app.get("/api/health", (c) => c.json(ok({ status: "ok" })));

  return app;
}
