// src/routers/articles.ts
// 文章下发 API：GET /api/articles/today、GET /api/articles?date=YYYY-MM-DD。
// 仅已过审（approved）文章，需 App JWT（AuthUser）；无 date 参数时默认配置时区的今天。
// 非法/任意字符串 date 不做校验（参数化查询无注入面），无匹配行即返回空数组。
import { Hono } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { attachErrorHandler, ok } from "../response";
import { resolveAuthUser } from "../auth";
import { localDate } from "../engine/utils/time";
import { listApprovedByDate } from "../services/article_reader";

export function articlesRouter(db: Database, cfg: ServerConfig): Hono {
  const app = new Hono();
  attachErrorHandler(app);

  app.get("/api/articles/today", (c) => {
    resolveAuthUser(db, cfg, c.req.header("authorization"));
    return c.json(ok(listApprovedByDate(db, localDate(cfg.timeZone))));
  });

  app.get("/api/articles", (c) => {
    resolveAuthUser(db, cfg, c.req.header("authorization"));
    const date = c.req.query("date") ?? localDate(cfg.timeZone);
    return c.json(ok(listApprovedByDate(db, date)));
  });

  return app;
}
