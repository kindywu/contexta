import { Hono } from "hono";
import type { Context } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import type { AppConfig } from "../engine/config";
import { generateDailyArticles } from "../engine/graph/daily";
import { localDate } from "../engine/utils/time";
import { attachErrorHandler, badRequest, notFound, ok } from "../response";
import { streamSSE } from "hono/streaming";
import { adminService } from "../services/admin_service";
import * as adminArticles from "../services/admin_articles";
import { requireAdminAuth, type ApiEnv } from "../middleware/require_auth";
import {
  approveArticle,
  ensureReviewRows,
  rejectArticle,
  retrySlot,
  toSlotRow,
  type GenFn,
  type ReviewCtx,
} from "../services/review_service";
import { notifyDailyResult, type DailyNotifyFn } from "../services/feishu_notify";

/** 手动补生成注入 seam（测试注入假实现；缺省 = 引擎 generateDailyArticles）。 */
export type GenDailyFn = (args: { runDate: string; config?: AppConfig }) => Promise<unknown>;

/** adminRouter 构造可注入项：gen = 槽位重跑生成（reject/retry 端点），genDaily = 每日批量生成。 */
export interface AdminRouterOpts {
  gen?: GenFn;
  genDaily?: GenDailyFn;
  /** 每日生成完成通知 seam（测试注入假实现；缺省 = notifyDailyResult 闭包）。 */
  notify?: DailyNotifyFn;
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
): Hono<ApiEnv> {
  const app = new Hono<ApiEnv>();
  attachErrorHandler(app);
  const ctx: ReviewCtx = { db, serverCfg: cfg, engineCfg, gen: opts.gen };
  const genDaily: GenDailyFn = opts.genDaily ?? generateDailyArticles;
  const notify: DailyNotifyFn =
    opts.notify ?? ((args) => notifyDailyResult({ db, serverCfg: cfg, engineCfg }, args));

  app.post("/api/admin/login", async (c) => {
    const body = await c.req.json<{ username?: string; password?: string }>();
    const token = adminService.login(db, cfg, body.username ?? "", body.password ?? "");
    return c.json(ok({ token }));
  });

  // 除 login（公开放行）外全部 /api/admin/* 需 Admin 认证
  app.use("/api/admin/*", requireAdminAuth(db, cfg));

  // ---------- 用户 / 配额 / 用量 ----------

  app.get("/api/admin/users", (c) => {
    return c.json(ok(adminService.listUsers(db, cfg)));
  });

  app.post("/api/admin/users/:phone/ban", async (c) => {
    const body = await readJson<{ reason?: string }>(c);
    adminService.setStatus(db, c.req.param("phone"), "banned", body.reason);
    return c.json(ok({}));
  });

  app.post("/api/admin/users/:phone/unban", (c) => {
    adminService.setStatus(db, c.req.param("phone"), "normal", null);
    return c.json(ok({}));
  });

  app.put("/api/admin/users/:phone/quota", async (c) => {
    const body = await readJson<{ word_daily?: unknown }>(c);
    const wd = body.word_daily;
    // 只接受正整数或 null（null = 清覆盖）：非数字会被 SQLite 当 TEXT 存储，
    // 配额比较恒 false → 该用户配额永久失效（无限烧钱），故入口硬校验。
    if (wd !== null && (typeof wd !== "number" || !Number.isInteger(wd) || wd <= 0)) {
      throw badRequest("word_daily must be a positive integer or null");
    }
    adminService.setQuota(db, c.req.param("phone"), wd);
    return c.json(ok({}));
  });

  app.get("/api/admin/usage", (c) => {
    return c.json(ok(adminService.usageReport(db, cfg)));
  });

  // ---------- 文章列表 / 详情 / 编辑 ----------

  app.get("/api/admin/articles", (c) => {
    const today = localDate(cfg.timeZone);
    const startDate = c.req.query("start_date") ?? today;
    const endDate = c.req.query("end_date") ?? today;
    for (const [name, v] of [["start_date", startDate], ["end_date", endDate]] as const) {
      if (!isValidIsoDate(v)) throw badRequest(`${name} must be a valid YYYY-MM-DD date`);
    }
    if (startDate > endDate) throw badRequest("start_date must be <= end_date");
    const status = c.req.query("status") ?? "";
    if (status !== "" && !["pending_review", "approved", "rejected"].includes(status)) {
      throw badRequest("invalid status");
    }
    const pageRaw = c.req.query("page") ?? "1";
    if (!/^\d+$/.test(pageRaw) || pageRaw === "0") throw badRequest("page must be a positive integer");
    const pageSizeRaw = c.req.query("page_size") ?? "15";
    if (!["15", "30", "45"].includes(pageSizeRaw)) {
      throw badRequest("page_size must be 15, 30 or 45");
    }
    const sortBy = c.req.query("sort_by") ?? "run_date";
    if (!adminArticles.ARTICLE_SORTABLE.includes(sortBy as never)) throw badRequest("invalid sort_by");
    const sortDirRaw = (c.req.query("sort_dir") ?? "desc").toLowerCase();
    if (sortDirRaw !== "asc" && sortDirRaw !== "desc") throw badRequest("invalid sort_dir");
    return c.json(
      ok(
        adminArticles.listArticles(db, {
          startDate,
          endDate,
          status: status || undefined,
          page: Number(pageRaw),
          pageSize: Number(pageSizeRaw),
          sortBy,
          sortDir: sortDirRaw,
        }),
      ),
    );
  });

  app.get("/api/admin/articles/:id", (c) => {
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not found");
    return c.json(ok(adminArticles.getArticleDetail(db, id)));
  });

  app.put("/api/admin/articles/:id", async (c) => {
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not editable");
    const body = await readJson<{ title?: unknown; paragraphs?: unknown }>(c);
    adminArticles.updateArticleContent(db, id, body.title, body.paragraphs);
    return c.json(ok({}));
  });

  app.post("/api/admin/articles/:id/approve", (c) => {
    const admin = c.get("adminUser")!;
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not reviewable");
    approveArticle(db, id, admin.username);
    return c.json(ok({}));
  });

  app.post("/api/admin/articles/:id/reject", async (c) => {
    const admin = c.get("adminUser")!;
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("article not reviewable");
    const body = await readJson<{ reason?: string }>(c);
    await rejectArticle(ctx, id, body.reason, admin.username);
    return c.json(ok({}));
  });

  // ---------- 槽位重跑 / 手动补生成 ----------

  // 异常槽位列表（manage 摘要"异常槽位"区块数据源）：时间段内非 success 槽位（error/rejected），
  // 含无文章行的 error 槽（articles 视角不可见）——管理端据此展示失败槽并给重跑入口。
  app.get("/api/admin/slots", (c) => {
    const today = localDate(cfg.timeZone);
    const startDate = c.req.query("start_date") ?? today;
    const endDate = c.req.query("end_date") ?? today;
    for (const [name, v] of [["start_date", startDate], ["end_date", endDate]] as const) {
      if (!isValidIsoDate(v)) throw badRequest(`${name} must be a valid YYYY-MM-DD date`);
    }
    if (startDate > endDate) throw badRequest("start_date must be <= end_date");
    const items = db
      .query(
        `SELECT id, slot_index, difficulty, status, article_id, thread_id, updated_at
         FROM batch_slots
         WHERE run_date BETWEEN ? AND ? AND status != 'success'
         ORDER BY run_date, slot_index`,
      )
      .all(startDate, endDate);
    return c.json(ok({ items }));
  });

  app.post("/api/admin/slots/:id/retry", async (c) => {
    const id = paramId(c.req.param("id"));
    if (!id) throw notFound("slot not found");
    const row = db.query("SELECT * FROM batch_slots WHERE id = ?").get(id) as
      | Record<string, unknown>
      | undefined;
    if (!row) throw notFound("slot not found");
    // 槽位状态守卫：只允许 error/rejected（无文章）槽重跑——success 槽的当前文章
    // 若已 approved，直连 API 重跑会静默下架已上线文章。pending（生成中）同样禁止。
    if (row.status !== "error" && row.status !== "rejected") {
      throw badRequest("slot not retryable");
    }
    // SSE：重跑为分钟级（WebView/LLM），进度流回传——前端弹窗实时展示阶段事件；
    // 心跳 8s < Bun.serve 默认 idleTimeout 10s（不该调大 idleTimeout 治标，见 main.ts 注释）。
    return streamSSE(c, async (stream) => {
      const heartbeat = setInterval(() => stream.write(`: ping\n\n`), 8_000);
      try {
        await retrySlot(ctx, toSlotRow(row), (stage, detail) =>
          stream.writeSSE({ event: "progress", data: JSON.stringify({ stage, detail }) }),
        );
        await stream.writeSSE({ event: "done", data: "{}" });
      } catch (e) {
        await stream.writeSSE({
          event: "error",
          data: JSON.stringify({ message: e instanceof Error ? e.message : String(e) }),
        });
      } finally {
        clearInterval(heartbeat);
      }
    });
  });

  app.post("/api/admin/articles/generate", async (c) => {
    const body = await readJson<{ date?: string }>(c);
    const date = body.date;
    if (typeof date !== "string" || !isValidIsoDate(date)) {
      throw badRequest("date must be a valid YYYY-MM-DD date");
    }
    const startedAt = new Date();
    try {
      await genDaily({ runDate: date, config: engineCfg });
    } catch (err) {
      // 整体失败也发通知（未收口报告；步骤错误 = 本次抛错），随后保持 500 语义上抛
      await notify({
        runDate: date,
        startedAt,
        endedAt: new Date(),
        stepErrors: [`引擎生成抛错: ${err instanceof Error ? err.message : String(err)}`],
      });
      throw err;
    }
    ensureReviewRows(db); // 补生成的 success 槽位建立待审行（引擎不建，收口在此）
    await notify({ runDate: date, startedAt, endedAt: new Date(), stepErrors: [] });
    return c.json(ok({}));
  });

  return app;
}
