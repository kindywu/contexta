import { Hono } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { attachErrorHandler, ok } from "../response";
import { adminService } from "../services/admin_service";

/** 本任务只实现 POST /api/admin/login；其余管理端点 Task 8 增补。 */
export function adminRouter(db: Database, cfg: ServerConfig): Hono {
  const app = new Hono();
  attachErrorHandler(app);

  app.post("/api/admin/login", async (c) => {
    const body = await c.req.json<{ username?: string; password?: string }>();
    const token = adminService.login(db, cfg, body.username ?? "", body.password ?? "");
    return c.json(ok({ token }));
  });

  return app;
}
