// src/main.ts
// 服务组装入口（对齐旧 Rust main.rs）：配置校验（时区硬闸）→ 数据库 schema →
// admin seed → 日志初始化（web 日志 server-<date>.log + stdout；生成日志 daily-<date>.log
// 仅文件）→ Hono app（/api 路由 + /admin 静态托管 + 顶层 onError）→ Bun.serve →
// 每日窗口任务后台启动（启动不生成文章）→ SIGINT/SIGTERM 优雅退出。
// buildApp 独立导出供冒烟测试（app.request 直连，不起真实端口）。
import { mkdirSync, existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Database } from "bun:sqlite";
import { Hono } from "hono";
import type { Context } from "hono";
import { serveStatic } from "hono/bun";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import { DEFAULT_LOG_DIR, loadServerConfig, type ServerConfig } from "./config";
import { ensureServerSchema, seedAdminIfNeeded } from "./db";
import { assertSystemTimezone, loadConfig, type AppConfig } from "./engine/config";
import { ensureSchema } from "./engine/db";
import { cleanupOldLogs, initLog } from "./engine/graph/log";
import { ApiError, attachErrorHandler, badRequest, errorBody, internal } from "./response";
import { adminRouter } from "./routers/admin";
import { articlesRouter } from "./routers/articles";
import { authRouter } from "./routers/auth";
import { healthRouter } from "./routers/health";
import { llmRouter } from "./routers/llm";
import { DailyTask } from "./services/daily_task";
import { initServerLog, serverError, serverLog } from "./services/server_log";

/** dist 缺失时的占位文案（Task 12 构建出 admin-ui/dist 后即真页面）。 */
export const ADMIN_PLACEHOLDER = "admin-ui not built";

/** buildApp 组装点可注入项：adminDistDir = admin-ui/dist 路径（测试注入临时目录隔离）。 */
export interface BuildAppOpts {
  adminDistDir?: string;
}

/** 缺省 dist 目录：模块相对定位（src/main.ts → 仓库 impl/server/admin-ui/dist），不依赖 cwd。 */
export function defaultAdminDistDir(): string {
  return join(import.meta.dir, "..", "admin-ui", "dist");
}

/**
 * 挂载 admin 静态托管：
 * - dist/index.html 存在 → serveStatic（/admin/* → root + 剥离 /admin 前缀）+ SPA 回退 index.html；
 * - 不存在 → /admin 与 /admin/* 均为 200 占位文案（待 Task 12 构建后即真页面）。
 */
function mountAdmin(app: Hono, distDir: string): void {
  const indexHtmlPath = join(distDir, "index.html");
  if (existsSync(indexHtmlPath)) {
    const indexHtml = readFileSync(indexHtmlPath, "utf8");
    // index.html 不缓存：防浏览器留存旧 index 引用已删除的旧哈希资源，
    // 命中 SPA 回退后以 text/html 应答 → 破 UI。静态资源（assets/*）不受影响。
    const sendIndex = (c: Context) => {
      c.header("Cache-Control", "no-cache");
      return c.html(indexHtml);
    };
    app.get("/admin", sendIndex);
    app.get(
      "/admin/*",
      serveStatic({
        root: distDir,
        rewriteRequestPath: (p) => p.replace(/^\/admin\/?/, ""),
      }),
    );
    app.get("/admin/*", sendIndex); // SPA 前端路由回退
  } else {
    app.get("/admin", (c) => c.text(ADMIN_PLACEHOLDER));
    app.get("/admin/*", (c) => c.text(ADMIN_PLACEHOLDER));
  }
  app.get("/", (c) => c.redirect("/admin"));
}

/**
 * 组装 Hono app（可测试组装点，不启端口）：
 * /api/* 路由全部以 app.route("/", subApp) 挂载——子路由自带 attachErrorHandler，
 * 子路由内 ApiError/SyntaxError 就地消化不上抛；
 * 顶层 onError 只兜 main 侧（静态/重定向）与计划外异常。
 */
export function buildApp(
  db: Database,
  cfg: ServerConfig,
  engineCfg: AppConfig,
  opts: BuildAppOpts = {},
): Hono {
  const app = new Hono();

  app.route("/", healthRouter());
  app.route("/", authRouter(db, cfg));
  app.route("/", llmRouter(db, cfg));
  app.route("/", articlesRouter(db, cfg));
  app.route("/", adminRouter(db, cfg, engineCfg));

  mountAdmin(app, opts.adminDistDir ?? defaultAdminDistDir());

  app.onError((err, c) => {
    if (err instanceof SyntaxError) {
      // 畸形 JSON body：仅来自 main 侧未保护的 c.req.json()（子路由侧同名分支见
      // attachErrorHandler）；带保护调用不会走到这里。记日志便于排查畸形请求。
      serverError("invalid JSON body:", err);
      return c.json(errorBody(badRequest("invalid JSON body")), 400);
    }
    if (err instanceof ApiError) {
      return c.json(errorBody(err), err.status as ContentfulStatusCode);
    }
    serverError("internal error:", err);
    return c.json(errorBody(internal(err)), 500);
  });

  return app;
}

/**
 * 服务入口：时区硬闸失败/配置缺失 → console.error + exit(1)（不启动服务）。
 */
export async function main(): Promise<void> {
  // 1) 引擎配置 + 时区硬校验（配置时区 ≠ 系统时区 → 拒绝运行）
  let engineCfg: AppConfig;
  let cfg: ServerConfig;
  try {
    engineCfg = loadConfig();
    assertSystemTimezone(engineCfg.timezone);
    // 2) 服务端配置（PORT/JWT_SECRET/限流/每日生成窗口等）
    cfg = loadServerConfig();
  } catch (err) {
    serverError(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  // 2.5) 日志：web 日志（logs/server-<date>.log + stdout 保留）+ 生成日志
  // （logs/daily-<date>.log，仅文件）分离；启动即清理 7 天前的旧日志。
  initServerLog(DEFAULT_LOG_DIR, engineCfg.timezone);
  initLog(DEFAULT_LOG_DIR, engineCfg.timezone, { prefix: "daily", echo: false });
  cleanupOldLogs(DEFAULT_LOG_DIR, 7, engineCfg.timezone);

  // 3) 数据库：引擎 4 表 + 服务端表（父目录不存在先建——dbPath 与 checkpointPath 各自建，
  //    两者父目录可能不同：如 DB_PATH=/tmp/x.db + CHECKPOINT_PATH=./data/langgraph.sqlite，
  //    BunSqliteCheckpointer 直接打开文件且引擎侧无目录创建者，不建则每日任务静默失败）
  const dbPath = engineCfg.dbPath;
  mkdirSync(dirname(dbPath), { recursive: true });
  mkdirSync(dirname(engineCfg.checkpointPath), { recursive: true });
  const db = new Database(dbPath);
  ensureSchema(db);
  ensureServerSchema(db);

  // 4) 初始 admin（ADMIN_INIT_PASSWORD 设置时 seed，无则跳过）
  if (cfg.adminInitPassword) {
    await seedAdminIfNeeded(db, "admin", cfg.adminInitPassword);
  }

  // 5) 组装 + 启动 HTTP 服务
  const app = buildApp(db, cfg, engineCfg);
  const server = Bun.serve({ port: cfg.port, fetch: app.fetch });
  serverLog(`[server] listening on :${cfg.port} (db: ${dbPath})`);

  // 6) 每日任务后台启动（窗口触发定时循环：启动不生成文章，错过窗口即跳过）
  new DailyTask({ db, engineCfg, serverCfg: cfg }).start();

  // 7) 优雅退出：SIGINT/SIGTERM → server.stop() + exit(0)；二次信号强制退出
  let shuttingDown = false;
  const shutdown = (signal: string) => {
    if (shuttingDown) {
      serverError(`[server] ${signal} 二次信号，强制退出`);
      process.exit(1);
    }
    shuttingDown = true;
    serverLog(`[server] ${signal} 收到，优雅退出…`);
    server.stop();
    process.exit(0);
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
}

// 直接执行（bun run src/main.ts）；被测试 import 时不启动（buildApp 才是测试面）
if (import.meta.main) {
  main().catch((err) => {
    serverError("启动失败:", err);
    process.exit(1);
  });
}
