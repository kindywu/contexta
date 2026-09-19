// tests/auth.test.ts
import { Database } from "bun:sqlite";
import { describe, expect, test } from "bun:test";
import { ensureServerSchema, seedAdminIfNeeded } from "../src/db";
import { authRouter } from "../src/routers/auth";
import { authService } from "../src/services/auth_service";
import { adminRouter } from "../src/routers/admin";
import { resolveAuthUser } from "../src/auth";
import { loadServerConfig } from "../src/config";
import type { AppConfig } from "../src/engine/config";

const cfg = loadServerConfig({ JWT_SECRET: "s".repeat(32), ADMIN_JWT_SECRET: "a".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" });
// Task 8 起 adminRouter 签名扩容（第三参 engineCfg）：本文件只用 login，占位配置即可
const engineCfg: AppConfig = {
  llmApiKey: "k",
  llmBaseUrl: "https://api.deepseek.com",
  llmModel: "m",
  timezone: "Asia/Shanghai",
  dbPath: ":memory:",
  checkpointPath: ":memory:",
  outputDir: "/tmp",
  browserConcurrency: 2,
  slotConcurrency: 5,
};
const db = new Database(":memory:");
ensureServerSchema(db);
const app = authRouter(db, cfg);
app.route("/", adminRouter(db, cfg, engineCfg));

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

  test("preview：第 3 台设备将挤掉最旧会话（含设备名与时间）且无副作用", async () => {
    // 直调 service：HTTP 路由的 device_name 透传属 Task 4，预置带名字的会话只能走 service
    const t1 = authService.login(db, cfg, "13300000000", "p1", "Xiaomi 14").token;
    authService.login(db, cfg, "13300000000", "p2", "iPad");
    const evicted = authService.previewEvictions(db, "13300000000", "p3");
    expect(evicted).toHaveLength(1);
    expect(evicted[0].device_id).toBe("p1");
    expect(evicted[0].device_name).toBe("Xiaomi 14");
    expect(typeof evicted[0].issued_at).toBe("number");
    // 预览无副作用：p1 的既有 token 仍有效
    expect((await login(t1)).status).toBe(200); // login() = 文件顶部 /api/auth/me 辅助
  });

  test("preview：已是活跃 2 台之一的设备 → 空", async () => {
    const loginDevice = (device: string) =>
      app.request("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ phone: "13300000001", device_id: device }),
      });
    await loginDevice("q1");
    await loginDevice("q2");
    expect(authService.previewEvictions(db, "13300000001", "q1")).toEqual([]);
  });

  test("login：第 3 台登录返回实际挤掉的设备", async () => {
    const loginDevice = (device: string) =>
      app.request("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ phone: "13300000002", device_id: device }),
      });
    await loginDevice("r1");
    await loginDevice("r2");
    const { data } = await (await loginDevice("r3")).json();
    expect(data.evicted).toHaveLength(1);
    expect(data.evicted[0].device_id).toBe("r1");
  });

  test("流水账：被挤写 evicted、同设备重登写 relogin、登出不写", async () => {
    const loginDevice = (device: string) =>
      app.request("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ phone: "13300000003", device_id: device, device_name: "Dev" }),
      });
    const rows = () =>
      db.query(`SELECT device_id, reason FROM device_evictions WHERE phone=? ORDER BY id`)
        .all("13300000003") as { device_id: string; reason: string }[];
    await loginDevice("s1");
    await loginDevice("s1"); // 同设备重登 → relogin
    expect(rows()).toEqual([{ device_id: "s1", reason: "relogin" }]);
    const t2 = (await (await loginDevice("s2")).json()).data.token;
    await loginDevice("s3"); // 挤掉 s1（issued_at 最旧）→ evicted
    expect(rows()[1]).toEqual({ device_id: "s1", reason: "evicted" });
    // 登出不记账：logout 删除会话行，但流水表不新增
    await app.request("/api/auth/logout", {
      method: "POST",
      headers: { authorization: `Bearer ${t2}`, "content-type": "application/json" },
      body: JSON.stringify({ device_id: "s2" }),
    });
    expect(rows()).toHaveLength(2);
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
  test("双密钥互斥：Admin 令牌打 App 接口、App 令牌打 Admin 接口均 401 TOKEN_EXPIRED", async () => {
    const adminTok = (await (await app.request("/api/admin/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ username: "admin", password: "pw-123456" }) })).json()).data.token;
    // Admin 令牌（adminJwtSecret 签发）→ App 接口：验签失败，不再走到会话比对
    const me = await app.request("/api/auth/me", { headers: { authorization: `Bearer ${adminTok}` } });
    expect(me.status).toBe(401);
    expect((await me.json()).error_code).toBe("TOKEN_EXPIRED");
    // App 令牌（appJwtSecret 签发）→ Admin 接口：验签失败
    const appTok = (await (await app.request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ phone: "13400000000", device_id: "d" }) })).json()).data.token;
    const users = await app.request("/api/admin/users", { headers: { authorization: `Bearer ${appTok}` } });
    expect(users.status).toBe(401);
    expect((await users.json()).error_code).toBe("TOKEN_EXPIRED");
  });
});
