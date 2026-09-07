// tests/middleware.test.ts
// 中间件行为：require_auth（登录保护——拦截需要登录的请求、公开路径放行、未知路径不误拦、
// 认证语义保持 401 TOKEN_EXPIRED / EVICTED、403 BANNED）+ requestLogger（匿名 / App 用户
// 打码手机号 / admin 身份均落 server-<今天>.log）。经 buildApp 全链路验证。
import { Database } from "bun:sqlite";
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ensureServerSchema, seedAdminIfNeeded } from "../src/db";
import { loadServerConfig } from "../src/config";
import { loadConfig } from "../src/engine/config";
import { ensureSchema } from "../src/engine/db";
import { localDate } from "../src/engine/utils/time";
import { buildApp } from "../src/main";
import { initServerLog } from "../src/services/server_log";

const TZ = "Asia/Shanghai";

/** 真库（:memory:） + 双 schema + 配置，buildApp 产出完整 app（含日志中间件）。 */
function makeApp() {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  const cfg = loadServerConfig({ JWT_SECRET: "s".repeat(32), ADMIN_JWT_SECRET: "a".repeat(32), LLM_API_KEY: "k", TIMEZONE: TZ });
  const engineCfg = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "mw-cp.sqlite"),
    outputDir: join(tmpdir(), "mw-out"),
  };
  return { app: buildApp(db, cfg, engineCfg), db };
}

describe("require_auth 登录保护", () => {
  test("App 受保护路径无 token → 401 TOKEN_EXPIRED", async () => {
    const { app } = makeApp();
    for (const [path, init] of [
      ["/api/auth/me", {}],
      ["/api/auth/logout", { method: "POST" }],
      ["/api/llm/word-lookup", { method: "POST" }],
    ] as const) {
      const res = await app.request(path, init);
      expect(res.status).toBe(401);
      expect((await res.json()).error_code).toBe("TOKEN_EXPIRED");
    }
  });

  test("Admin 受保护路径无 token → 401 TOKEN_EXPIRED", async () => {
    const { app } = makeApp();
    const res = await app.request("/api/admin/users");
    expect(res.status).toBe(401);
    expect((await res.json()).error_code).toBe("TOKEN_EXPIRED");
  });

  test("公开路径放行：login 不受守卫拦截（错误密码 → INVALID_CREDENTIALS 而非 TOKEN_EXPIRED）", async () => {
    const { app } = makeApp();
    const res = await app.request("/api/admin/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "wrong" }),
    });
    expect(res.status).toBe(401);
    expect((await res.json()).error_code).toBe("INVALID_CREDENTIALS");
    const health = await app.request("/api/health");
    expect(health.status).toBe(200);
  });

  test("未知 /api 路径不被守卫误拦截 → 404", async () => {
    const { app } = makeApp();
    const res = await app.request("/api/nonexistent");
    expect(res.status).toBe(404);
  });
});

describe("requestLogger 请求访问日志", () => {
  const logDir = mkdtempSync(join(tmpdir(), "mw-log-"));
  let app: ReturnType<typeof makeApp>["app"];
  let db: Database;

  beforeAll(() => {
    initServerLog(logDir, TZ);
    ({ app, db } = makeApp());
  });

  afterAll(() => {
    rmSync(logDir, { recursive: true, force: true });
  });

  function logFile(channel: "app" | "web"): string {
    const prefix = channel === "app" ? "app" : "admin";
    return readFileSync(join(logDir, `${prefix}-${localDate(TZ)}.log`), "utf8");
  }

  test("匿名请求记 user=anon（app 通道，含 404）", async () => {
    await app.request("/api/health");
    await app.request("/api/nothing-here");
    const log = logFile("app");
    expect(log).toContain("200 GET /api/health user=anon");
    expect(log).toContain("404 GET /api/nothing-here user=anon");
  });

  test("App 登录后记打码手机号（app 文件，完整号码不落任何日志）", async () => {
    const login = await app.request("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13800000000", device_id: "dev1" }),
    });
    const token = (await login.json()).data.token;
    const me = await app.request("/api/auth/me", { headers: { authorization: `Bearer ${token}` } });
    expect(me.status).toBe(200);
    const log = logFile("app");
    expect(log).toContain(`200 GET /api/auth/me user=138****0000`);
    expect(log).not.toContain("13800000000"); // 完整号码不落日志
  });

  test("Admin 请求记 admin: 身份（web 通道，与 app 文件分离）", async () => {
    await seedAdminIfNeeded(db, "admin", "pw-123456");
    const login = await app.request("/api/admin/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "pw-123456" }),
    });
    const token = (await login.json()).data.token;
    const users = await app.request("/api/admin/users", {
      headers: { authorization: `Bearer ${token}` },
    });
    expect(users.status).toBe(200);
    const web = logFile("web");
    expect(web).toContain(`200 GET /api/admin/users user=admin:admin`);
    expect(web).not.toContain("user=138"); // app 请求不落入 web 文件
    expect(logFile("app")).not.toContain("user=admin:admin"); // web 请求不落入 app 文件
  });
});
