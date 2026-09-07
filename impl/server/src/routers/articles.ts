// src/routers/articles.ts
// 文章投放 API：GET /api/articles/delivery?difficulty=LOW&count=3。
// 替代旧 today / ?date=（App 已切换，唯一使用方）；参数校验 400 BAD_PARAM；
// count 超配额不报错（服务端截断，见 article_delivery.ts 注释）。
import { Hono } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { attachErrorHandler, badRequest, ok } from "../response";
import { Difficulty } from "../engine/schema";
import { deliverArticles } from "../services/article_delivery";
import { requireAppAuth, type ApiEnv } from "../middleware/require_auth";

export function articlesRouter(db: Database, cfg: ServerConfig): Hono<ApiEnv> {
  const app = new Hono<ApiEnv>();
  attachErrorHandler(app);

  app.use("/api/articles/delivery", requireAppAuth(db, cfg));

  app.get("/api/articles/delivery", (c) => {
    const auth = c.get("appUser")!;
    const parsed = Difficulty.safeParse(c.req.query("difficulty"));
    if (!parsed.success) throw badRequest("difficulty 应为 LOW|MEDIUM|HIGH");
    const count = Number(c.req.query("count"));
    if (!Number.isInteger(count) || count < 1) throw badRequest("count 应为 ≥1 的整数");
    const { deliveryDate, articles } = deliverArticles(db, {
      phone: auth.phone,
      deviceId: auth.deviceId,
      difficulty: parsed.data,
      count,
      nowMs: Date.now(),
      timeZone: cfg.timeZone,
    });
    // 服务端内部字段 deliveryDate 在此映射为 App 契约 snake_case（DTO fromJson 按此解析）
    return c.json(ok({ delivery_date: deliveryDate, articles }));
  });

  return app;
}
