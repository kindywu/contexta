import { describe, expect, test } from "bun:test";
import { formatWindow, loadServerConfig } from "../src/config";

describe("loadServerConfig", () => {
  const base = { JWT_SECRET: "x".repeat(32), ADMIN_JWT_SECRET: "y".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" };
  test("缺 JWT_SECRET 抛错", () => {
    expect(() => loadServerConfig({})).toThrow(/JWT_SECRET/);
  });
  test("缺 ADMIN_JWT_SECRET 抛错", () => {
    expect(() => loadServerConfig({ ...base, ADMIN_JWT_SECRET: undefined })).toThrow(/ADMIN_JWT_SECRET/);
  });
  test("JWT_SECRET 短于 32 字符抛错", () => {
    expect(() => loadServerConfig({ ...base, JWT_SECRET: "short" })).toThrow(/32/);
  });
  test("ADMIN_JWT_SECRET 短于 32 字符抛错", () => {
    expect(() => loadServerConfig({ ...base, ADMIN_JWT_SECRET: "short" })).toThrow(/32/);
  });
  test("默认值正确", () => {
    const c = loadServerConfig(base);
    expect(c.port).toBe(8080);
    expect(c.wordQuotaDaily).toBe(200);
    expect(c.cacheTtlDays).toBe(30);
    expect(c.cacheMaxRows).toBe(5000);
    expect(c.dailyGenerateWindow).toEqual({ start: 480, end: 495 }); // 默认 08:00-08:15（分钟数）
    expect(formatWindow(c.dailyGenerateWindow)).toBe("08:00-08:15");
    expect(c.llmTimeoutSecs).toBe(90);
    expect(c.regenerateLimit).toBe(3);
    expect(c.adminInitPassword).toBeUndefined();
  });
  test("可覆盖", () => {
    const c = loadServerConfig({ ...base, PORT: "9000", WORD_QUOTA_DAILY: "50", REGENERATE_LIMIT: "5", ADMIN_INIT_PASSWORD: "pw" });
    expect(c.port).toBe(9000);
    expect(c.wordQuotaDaily).toBe(50);
    expect(c.regenerateLimit).toBe(5);
    expect(c.adminInitPassword).toBe("pw");
  });
  test("TIMEZONE 缺失/非法抛错", () => {
    expect(() => loadServerConfig({ JWT_SECRET: "x".repeat(32) })).toThrow(/TIMEZONE/);
    expect(() => loadServerConfig({ ...base, TIMEZONE: "Mars/Olympus" })).toThrow(/时区/);
  });
  test("timeZone 透传", () => {
    expect(loadServerConfig(base).timeZone).toBe("Asia/Shanghai");
  });
  test("DAILY_GENERATE_WINDOW 可覆盖（12:00-12:30 → {start:720,end:750}）", () => {
    const c = loadServerConfig({ ...base, DAILY_GENERATE_WINDOW: "12:00-12:30" });
    expect(c.dailyGenerateWindow).toEqual({ start: 720, end: 750 });
    expect(formatWindow(c.dailyGenerateWindow)).toBe("12:00-12:30");
  });
  test("TLS 未配置 → 两个字段均 undefined（回退 HTTP）", () => {
    const c = loadServerConfig(base);
    expect(c.tlsCertPath).toBeUndefined();
    expect(c.tlsKeyPath).toBeUndefined();
  });
  test("TLS 只配一项抛错", () => {
    expect(() => loadServerConfig({ ...base, TLS_CERT_PATH: "/tmp/c.pem" })).toThrow(/同时配置/);
    expect(() => loadServerConfig({ ...base, TLS_KEY_PATH: "/tmp/k.pem" })).toThrow(/同时配置/);
  });
  test("TLS 路径文件不存在抛错（启动即失败，不留到 Bun.serve）", () => {
    expect(() =>
      loadServerConfig({ ...base, TLS_CERT_PATH: "/nonexistent/c.pem", TLS_KEY_PATH: "/nonexistent/k.pem" }),
    ).toThrow(/文件不存在/);
  });
  test("TLS 成对且文件存在 → 路径透传", () => {
    const c = loadServerConfig({
      ...base,
      TLS_CERT_PATH: __filename, // 任意存在的文件即可（此层只校验存在性）
      TLS_KEY_PATH: __filename,
    });
    expect(c.tlsCertPath).toBe(__filename);
    expect(c.tlsKeyPath).toBe(__filename);
  });
  test("DAILY_GENERATE_WINDOW 非法格式/边界抛错", () => {
    // 缺 "-" / 越界时刻 / start >= end 均拒绝
    expect(() => loadServerConfig({ ...base, DAILY_GENERATE_WINDOW: "0800-0815" })).toThrow(/格式/);
    expect(() => loadServerConfig({ ...base, DAILY_GENERATE_WINDOW: "25:00-08:15" })).toThrow(/HH:MM|格式/);
    expect(() => loadServerConfig({ ...base, DAILY_GENERATE_WINDOW: "08:60-09:00" })).toThrow(/HH:MM|格式/);
    expect(() => loadServerConfig({ ...base, DAILY_GENERATE_WINDOW: "08:15-08:00" })).toThrow(/start|开始|窗口/);
    expect(() => loadServerConfig({ ...base, DAILY_GENERATE_WINDOW: "08:00-08:00" })).toThrow(/start|开始|窗口/);
  });
});
