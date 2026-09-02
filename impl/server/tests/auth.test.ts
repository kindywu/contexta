// tests/auth.test.ts
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureServerSchema, seedAdminIfNeeded } from "../src/db";
import { authRouter } from "../src/routers/auth";
import { adminRouter } from "../src/routers/admin";
import { resolveAuthUser } from "../src/auth";
import { loadServerConfig } from "../src/config";

const cfg = loadServerConfig({ JWT_SECRET: "s".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" });
const db = new Database(":memory:");
ensureServerSchema(db);
const app = authRouter(db, cfg);
app.route("/", adminRouter(db, cfg));

async function login(token: string) { return await app.request("/api/auth/me", { headers: { authorization: `Bearer ${token}` } }); }

describe("auth", () => {
  test("login → me 200，token 携带 phone", async () => {
    const res = await app.request("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13800000000", device_id: "dev1" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.code).toBe(0);
    expect(typeof body.data.token).toBe("string");
    const me = await login(body.data.token);
    expect(me.status).toBe(200);
    expect((await me.json()).data).toEqual({ phone: "13800000000" });
  });
  test("重登后旧 token 失效（iat 精确匹配）", async () => {
    const first = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13900000000", device_id: "d1" }) })).json()).data.token;
    const second = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13900000000", device_id: "d1" }) })).json()).data.token;
    expect((await login(first)).status).toBe(401);      // 旧 token EVICTED
    const body = await (await login(first)).json();
    expect(body.error_code).toBe("EVICTED");
    // 新 token 有效（对齐 Rust 参考测试 relogin_invalidates_old_token）
    expect((await login(second)).status).toBe(200);
  });
  test("第三设备挤掉最旧会话", async () => {
    const t1 = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13700000000", device_id: "a" }) })).json()).data.token;
    const t2 = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13700000000", device_id: "b" }) })).json()).data.token;
    const t3 = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13700000000", device_id: "c" }) })).json()).data.token;
    expect((await login(t1)).status).toBe(401);
    expect((await login(t2)).status).toBe(200);
    expect((await login(t3)).status).toBe(200);
  });
  test("封禁 → 403 BANNED（先封禁后会话）", async () => {
    const token = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13600000000", device_id: "d" }) })).json()).data.token;
    db.run("UPDATE users SET status='banned' WHERE phone='13600000000'");
    const res = await login(token);
    expect(res.status).toBe(403);
    expect((await res.json()).error_code).toBe("BANNED");
  });
  test("logout 后 401 EVICTED", async () => {
    const token = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13500000000", device_id: "d" }) })).json()).data.token;
    await app.request("/api/auth/logout", { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ device_id: "d" }) });
    expect((await login(token)).status).toBe(401);
  });
  test("login 缺 phone/device_id → 400 BAD_PARAM", async () => {
    const res = await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "" }) });
    expect(res.status).toBe(400);
    expect((await res.json()).error_code).toBe("BAD_PARAM");
  });
});

describe("admin login", () => {
  test("密码错误/未知用户 → 401 TOKEN_EXPIRED（不区分）", async () => {
    await seedAdminIfNeeded(db, "admin", "pw-123456");
    const bad = await app.request("/api/admin/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "admin", password: "wrong" }) });
    expect(bad.status).toBe(401);
    const nf = await app.request("/api/admin/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "nobody", password: "x" }) });
    expect(nf.status).toBe(401);
  });
  test("正确密码 → token 可用", async () => {
    const res = await app.request("/api/admin/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "admin", password: "pw-123456" }) });
    expect(res.status).toBe(200);
    const { data } = await res.json();
    expect(typeof data.token).toBe("string");
  });
});
