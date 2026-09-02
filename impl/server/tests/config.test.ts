import { describe, expect, test } from "bun:test";
import { loadServerConfig } from "../src/config";

describe("loadServerConfig", () => {
  const base = { JWT_SECRET: "x".repeat(32), LLM_API_KEY: "k", TIMEZONE: "Asia/Shanghai" };
  test("缺 JWT_SECRET 抛错", () => {
    expect(() => loadServerConfig({})).toThrow(/JWT_SECRET/);
  });
  test("JWT_SECRET 短于 32 字符抛错", () => {
    expect(() => loadServerConfig({ ...base, JWT_SECRET: "short" })).toThrow(/32/);
  });
  test("默认值正确", () => {
    const c = loadServerConfig(base);
    expect(c.port).toBe(8080);
    expect(c.wordQuotaDaily).toBe(200);
    expect(c.cacheTtlDays).toBe(30);
    expect(c.cacheMaxRows).toBe(5000);
    expect(c.dailyGenerateHour).toBe(3);
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
});
