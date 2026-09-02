import { Hono } from "hono";
import type { Context } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { generateDailyArticles } from "../engine/graph/daily";
import { localDate } from "../engine/utils/time";
import { attachErrorHandler, badRequest, notFound, ok } from "../response";
import { resolveAdminAuth } from "../auth";
import { adminService } from "../services/admin_service";
import * as adminArticles from "../services/admin_articles";
import {
  approveArticle,
  ensureReviewRows,
  rejectArticle,
  retrySlot,
  toSlotRow,
  type GenFn,
  type ReviewCtx,
} from "../services/review_service";

/** 手动补生成注入 seam（测试注入假实现；缺省 = 引擎 generateDailyArticles）。 */
export type GenDailyFn = (args: { runDate: string; config?: AppConfig }) => Promise<unknown>;

/** adminRouter 构造可注入项：gen = 槽位重跑生成（reject/retry 端点），genDaily = 每日批量生成。 */
export interface AdminRouterOpts {
  gen?: GenFn;
  genDaily?: GenDailyFn;
}

/** 请求体安全解析：空体/非法 JSON → {}（交由各端点校验兜底 400/404，而非 500）。 */
async function readJson<T>(c: Context): Promise<Partial<T>> {
  try {
    return (await c.req.json()) as Partial<T>;
  } catch {
    return {};
  }
}

/** 路径参数转 id：非纯数字串 → undefined（资源不可能存在，调用方统一 404）。 */
function paramId(raw: string): number | undefined {
  if (!/^\d+$/.test(raw)) return undefined;
  return Number(raw);
}

/** 严格 ISO 日期（YYYY-MM-DD）：正则 + 回格式化全等（2026-02-30 → 03-02 不等 → 非法）。 */
export function isValidIsoDate(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return false;
  return d.toISOString().slice(0, 10) === s;
}

/**
 * 管理端路由（除 login 全部 AdminAuth）。
 * ctx（reject/retry 端点）由 adminRouter 构造：{ db, serverCfg: cfg, engineCfg, gen: opts.gen }；
 * gen 缺省 = 引擎 generateArticle，测试注入假实现。
 */
export function adminRouter(
  db: Database,
  cfg: ServerConfig,
  engineCfg: AppConfig,
  opts: AdminRouterOpts = {},
): Hono {
  const app = new Hono();
  attachErrorHandler(app);
  const ctx: ReviewCtx = { db, serverCfg: cfg, engineCfg, gen: opts.gen };
  const genDaily: GenDailyFn = opts.genDaily ?? generateDailyArticles;
  const auth = (c: Context) => resolveAdminAuth(db, cfg, c.req.header("authorization"));

  app.post("/api/admin/login", async (c) => {
    const body = await c.req.json<{ username?: string; password?: string }>();
    const token = adminService.login(db, cfg, body.username ?? "", body.password ?? "");
    return c.json(ok({ token }));
  });

  // ---------- 用户 / 配额 / 用量 ----------

  app.get("/api/admin/users", (c) => {
    auth(c);
    return c.json(ok(adminService.listUsers(db, cfg)));
  });

  app.post("/api/admin/users/:phone/ban", async (c) => {
    auth(c);
    const body = await readJson<{ reason?: string }>(c);
    adminService.setStatus(db, c.req.param("phone"), "banned", body.reason);
    return c.json(ok({}));
  });

  app.post("/api/admin/users/:phone/unban", (c) => {
    auth(c);
    adminService.setStatus(db, c.req.param("phone"), "normal", null);
    return c.json(ok({}));
  });

  app.put("/api/admin/users/:phone/quota", async (c) => {
    auth(c);
    const body = await readJson<{ word_daily?: number | null }>(c);
    adminService.setQuota(db, c.req.param("phone"), body.word_daily);
    return c.json(ok({}));
  });

  app.get("/api/admin/usage", (c) => {
    auth(c);
    return c.json(ok(adminService.usageReport(db, cfg)));
  });

  // ---------- 槽位审核视图 / 详情 / 编辑 ----------

  app.get("/api/admin/articles", (c) => {
    auth(c);
    const date = c.req.query("date") ?? localDate(cfg.timeZone);
    const status = c.req.query("status");
    return c.json(ok(adminArticles.listSlotsByDate(db, date, status || undefined)));
  });

  app.get("/api/admin/articles/:id", (c) => {
    auth(c);
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not found");
    return c.json(ok(adminArticles.getArticleDetail(db, id)));
  });

  app.put("/api/admin/articles/:id", async (c) => {
    auth(c);
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not editable");
    const body = await readJson<{ title?: unknown; paragraphs?: unknown }>(c);
    adminArticles.updateArticleContent(db, id, body.title, body.paragraphs);
    return c.json(ok({}));
  });

  app.post("/api/admin/articles/:id/approve", (c) => {
    const admin = auth(c);
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not reviewable");
    approveArticle(db, id, admin.username);
    return c.json(ok({}));
  });

  app.post("/api/admin/articles/:id/reject", async (c) => {
    const admin = auth(c);
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not reviewable");
    const body = await readJson<{ reason?: string }>(c);
    await rejectArticle(ctx, id, body.reason, admin.username);
    return c.json(ok({}));
  });

  // ---------- 槽位重跑 / 手动补生成 ----------

  app.post("/api/admin/slots/:id/retry", async (c) => {
    auth(c);
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("slot not found");
    const row = db.query("SELECT * FROM batch_slots WHERE id = ?").get(id) as
      | Record<string, unknown>
      | undefined;
    if (!row) throw notFound("slot not found");
    await retrySlot(ctx, toSlotRow(row));
    return c.json(ok({}));
  });

  app.post("/api/admin/articles/generate", async (c) => {
    auth(c);
    const body = await readJson<{ date?: string }>(c);
    const date = body.date;
    if (typeof date !== "string" || !isValidIsoDate(date)) {
      throw badRequest("date must be a valid YYYY-MM-DD date");
    }
    await genDaily({ runDate: date, config: engineCfg });
    ensureReviewRows(db); // 补生成的 success 槽位建立待审行（引擎不建，收口在此）
    return c.json(ok({}));
  });

  return app;
}
