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

  test("被挤行 by_device_name：下手设备本次不带名且无已存会话 → 不臆造（null）", async () => {
    const phone = "13300000004";
    // 直调 service：HTTP 路由的 device_name 透传属 Task 4（同 preview 用例）
    const loginDevice = (device: string, name?: string) =>
      authService.login(db, cfg, phone, device, name);
    loginDevice("t1", "iPad");
    loginDevice("t2", "Galaxy");
    loginDevice("t3", "Pixel"); // 挤掉 t1（issued_at 最旧）
    loginDevice("t4", "Watch"); // 挤掉 t2 → t2 的会话行已被删除
    loginDevice("t2"); // 不带名字重登：本次挤掉 t3
    const row = db
      .query(
        `SELECT by_device_id, by_device_name FROM device_evictions
         WHERE phone = ? AND device_id = 't3' AND reason = 'evicted' ORDER BY id DESC LIMIT 1`,
      )
      .get(phone) as { by_device_id: string; by_device_name: string | null };
    expect(row.by_device_id).toBe("t2");
    // t2 的会话行已被 t4 挤掉，没有可回退的名字（会话表 ≤2 行 ⟹ 下手方若已有会话就不会挤人）
    expect(row.by_device_name).toBe(null);
  });

  test("被挤行 by_device_name：存量库 >2 条会话时回退下手设备已存名字", async () => {
    const phone = "13300000005";
    // 直接造 3 条会话行：login 的裁剪不变量保证线上 ≤2 行，但存量/asset 库可能遗留更多
    const now = Date.now();
    const ins = db.query(
      "INSERT INTO device_sessions (phone, device_id, device_name, issued_at, last_active_at) VALUES (?, ?, ?, ?, ?)",
    );
    ins.run(phone, "d1", "iPad", now, now);
    ins.run(phone, "d2", "Galaxy", now + 1, now + 1);
    ins.run(phone, "d3", "Pixel", now + 2, now + 2);
    // d3 不带名字重登：previous 命中 d3（已存名字 'Pixel'），本次挤掉最旧的 d1
    const { evicted } = authService.login(db, cfg, phone, "d3");
    expect(evicted.map((e) => e.device_id)).toEqual(["d1"]);
    const row = db
      .query(
        `SELECT by_device_id, by_device_name FROM device_evictions
         WHERE phone = ? AND device_id = 'd1' AND reason = 'evicted' ORDER BY id DESC LIMIT 1`,
      )
      .get(phone) as { by_device_id: string; by_device_name: string | null };
    expect(row.by_device_id).toBe("d3");
    expect(row.by_device_name).toBe("Pixel"); // 回退 prior 已存名字（修复前为 null）
  });

  test("evictionDetail：结束与签发同刻（ended_at == sinceIssuedAt）仍算本 token 的失效事件", async () => {
    const phone = "13300000006";
    const now = Date.now();
    db.query(
      `INSERT INTO device_evictions
         (phone, device_id, device_name, reason, ended_at, by_device_id, by_device_name, by_issued_at, created_at)
       VALUES (?, 'old', 'iPad', 'evicted', ?, 'new', 'Pixel', ?, ?)`,
    ).run(phone, now, now + 1, now);
    const detail = authService.evictionDetail(db, phone, "old", now);
    expect(detail?.reason).toBe("evicted");
    expect(detail?.by.device_name).toBe("Pixel");
    // 严格早于签发时刻的结束事件属于更早的旧会话 → 不匹配
    expect(authService.evictionDetail(db, phone, "old", now + 1)).toBeUndefined();
  });

  test("被挤设备 401 EVICTED 带 detail（谁、何时）", async () => {
    // 直调 service 造带名字的会话：HTTP 路由的 device_name 透传属 Task 4（同 preview 用例）
    const loginDevice = (device: string, name?: string) =>
      authService.login(db, cfg, "13200000000", device, name);
    const t1 = loginDevice("v1", "Xiaomi 14").token;
    loginDevice("v2", "iPad");
    loginDevice("v3", "iPhone 15 Pro"); // 挤掉 v1
    const res = await login(t1); // 顶部辅助：GET /api/auth/me
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error_code).toBe("EVICTED");
    expect(body.detail.reason).toBe("evicted");
    expect(body.detail.by.device_id).toBe("v3");
    expect(body.detail.by.device_name).toBe("iPhone 15 Pro");
    expect(typeof body.detail.ended_at).toBe("number");
  });

  test("登出后的旧 token：401 EVICTED 无 detail（不编造设备）", async () => {
    const loginRes = await app.request("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13200000001", device_id: "w1" }),
    });
    const token = (await loginRes.json()).data.token;
    await app.request("/api/auth/logout", {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ device_id: "w1" }),
    });
    const res = await login(token);
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error_code).toBe("EVICTED");
    expect(body.detail).toBeUndefined();
  });

  test("同设备重登的旧 token：detail.reason = relogin", async () => {
    const loginDevice = () =>
      app.request("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ phone: "13200000002", device_id: "x1" }),
      });
    const old = (await (await loginDevice()).json()).data.token;
    await loginDevice();
    const res = await login(old); // 顶部辅助：GET /api/auth/me
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error_code).toBe("EVICTED");
    expect(body.detail.reason).toBe("relogin");
    expect(body.detail.by.device_id).toBe("x1");
  });

  test("preview 契约：缺参数 400；正常 200 且 snake_case", async () => {
    const bad = await app.request("/api/auth/login/preview", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13100000000" }),
    });
    expect(bad.status).toBe(400);
    expect((await bad.json()).error_code).toBe("BAD_PARAM");

    const okRes = await app.request("/api/auth/login/preview", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13100000000", device_id: "y1" }),
    });
    expect(okRes.status).toBe(200);
    expect((await okRes.json()).data).toEqual({ evicted: [] });
  });

  test("login 收 device_name 并落库（重登不覆盖已有名字）", async () => {
    await app.request("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13100000001", device_id: "z1", device_name: "Xiaomi 14" }),
    });
    const row = db
      .query("SELECT device_name FROM device_sessions WHERE phone = ? AND device_id = ?")
      .get("13100000001", "z1") as { device_name: string | null };
    expect(row.device_name).toBe("Xiaomi 14");
    // 旧版本重登（不带 device_name）→ 保留已存名字
    await app.request("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "13100000001", device_id: "z1" }),
    });
    const row2 = db
      .query("SELECT device_name FROM device_sessions WHERE phone = ? AND device_id = ?")
      .get("13100000001", "z1") as { device_name: string | null };
    expect(row2.device_name).toBe("Xiaomi 14");
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
