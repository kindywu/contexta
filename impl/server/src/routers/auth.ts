import { Hono } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { attachErrorHandler, badRequest, ok } from "../response";
import { resolveAuthUser } from "../auth";
import { authService } from "../services/auth_service";
import { issueAppToken, APP_TOKEN_TTL_SECS } from "../jwt";

export function authRouter(db: Database, cfg: ServerConfig): Hono {
  const app = new Hono();
  attachErrorHandler(app);

  app.post("/api/auth/login", async (c) => {
    const body = await c.req.json<{ phone?: string; device_id?: string; code?: string }>();
    if (!body.phone || !body.device_id) throw badRequest("phone and device_id required");
    const token = authService.login(db, cfg, body.phone, body.device_id);
    const expiresAt = Math.floor(Date.now() / 1000) + APP_TOKEN_TTL_SECS;
    return c.json(ok({ token, expires_at: expiresAt }));
  });

  app.post("/api/auth/logout", async (c) => {
    const user = resolveAuthUser(db, cfg, c.req.header("authorization"));
    const body = await c.req.json<{ device_id?: string }>();
    authService.logout(db, user.phone, body.device_id ?? "");
    return c.json(ok({}));
  });

  app.get("/api/auth/me", async (c) => {
    const user = resolveAuthUser(db, cfg, c.req.header("authorization"));
    return c.json(ok({ phone: user.phone }));
  });

  return app;
}
