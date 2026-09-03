// tests/smoke.test.ts
// 服务组装冒烟：buildApp + app.request()（不起真实端口）验证——
// 路由挂载（health/articles/llm）、envelope 错误（401 TOKEN_EXPIRED）、
// SyntaxError → 400 BAD_PARAM、admin 静态托管（dist 存在 → 真页面；不存在 → 占位文案、
// SPA 回退、/admin/assets 静态文件）、根路径重定向。
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadServerConfig } from "../src/config";
import { ensureServerSchema } from "../src/db";
import { loadConfig } from "../src/engine/config";
import { ensureSchema } from "../src/engine/db";
import { ADMIN_PLACEHOLDER, buildApp } from "../src/main";

const TZ = "Asia/Shanghai";

/** 真库（:memory:） + 双 schema + 配置，buildApp 产出完整 app（adminDistDir 可注入）。 */
function makeApp(adminDistDir?: string) {
  const db = new Database(":memory:");
  ensureSchema(db);
  ensureServerSchema(db);
  const cfg = loadServerConfig({
    JWT_SECRET: "s".repeat(32),
    LLM_API_KEY: "k",
    TIMEZONE: TZ,
  });
  const engineCfg = {
    ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
    dbPath: ":memory:",
    checkpointPath: join(tmpdir(), "smoke-cp.sqlite"),
    outputDir: join(tmpdir(), "smoke-out"),
  };
  return buildApp(db, cfg, engineCfg, { adminDistDir });
}

/** 保证不存在的 dist 目录（占位分支）。 */
function missingDistDir(): string {
  return join(tmpdir(), `ctxa-smoke-missing-${Math.random().toString(36).slice(2)}`);
}

/** 临时 dist：index.html + assets/app.js（真页面分支）。 */
function tempDistDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "ctxa-smoke-dist-"));
  writeFileSync(join(dir, "index.html"), "<html><body>admin index</body></html>");
  mkdirSync(join(dir, "assets"));
  writeFileSync(join(dir, "assets/app.js"), "console.log(1)");
  return dir;
}

describe("buildApp 服务组装冒烟", () => {
  test("GET /api/health → 200 {code:0,data:{status:ok}}", async () => {
    const app = makeApp();
    const res = await app.request("/api/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ code: 0, data: { status: "ok" } });
  });

  test("POST /api/auth/login 畸形 JSON → 400 BAD_PARAM（SyntaxError 映射）", async () => {
    const app = makeApp();
    const res = await app.request("/api/auth/login", { method: "POST", body: "{" });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({
      code: 400,
      message: "invalid JSON body",
      error_code: "BAD_PARAM",
    });
  });

  test("dist 不存在：GET /admin 与 /admin/* 均为 200 占位文案", async () => {
    const app = makeApp(missingDistDir());
    const root = await app.request("/admin");
    expect(root.status).toBe(200);
    expect(await root.text()).toContain(ADMIN_PLACEHOLDER);
    const deep = await app.request("/admin/anything");
    expect(deep.status).toBe(200);
    expect(await deep.text()).toContain(ADMIN_PLACEHOLDER);
  });

  test("dist 存在：/admin 服务 index.html，SPA 路由回退，assets 静态文件", async () => {
    const app = makeApp(tempDistDir());
    const index = await app.request("/admin");
    expect(index.status).toBe(200);
    expect(await index.text()).toContain("admin index");
    const deep = await app.request("/admin/login");
    expect(deep.status).toBe(200);
    expect(await deep.text()).toContain("admin index");
    const asset = await app.request("/admin/assets/app.js");
    expect(asset.status).toBe(200);
    expect(await asset.text()).toContain("console.log(1)");
  });

  test("根路径 / → 302 重定向 /admin", async () => {
    const app = makeApp();
    const res = await app.request("/");
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe("/admin");
  });

  test("GET /api/articles/delivery 无 token → 401 TOKEN_EXPIRED（路由已挂 + 鉴权生效）", async () => {
    const app = makeApp();
    const res = await app.request("/api/articles/delivery?difficulty=LOW&count=3");
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({
      code: 401,
      message: "unauthorized",
      error_code: "TOKEN_EXPIRED",
    });
  });

  test("POST /api/llm/word-lookup 无 token → 401 TOKEN_EXPIRED（路由已挂 + 鉴权生效）", async () => {
    const app = makeApp();
    const res = await app.request("/api/llm/word-lookup", { method: "POST" });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({
      code: 401,
      message: "unauthorized",
      error_code: "TOKEN_EXPIRED",
    });
  });
});
