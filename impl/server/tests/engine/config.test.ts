import { expect, test } from "bun:test";
import { assertSystemTimezone, loadConfig } from "../../src/engine/config";

const baseEnv = { LLM_API_KEY: "sk-test", TIMEZONE: "Asia/Shanghai" };

test("loadConfig: LLM_API_KEY 缺失抛错并提示 .env.example", () => {
  expect(() => loadConfig({})).toThrow(/LLM_API_KEY/);
  expect(() => loadConfig({})).toThrow(/\.env\.example/);
});

test("loadConfig: 缺省默认值正确", () => {
  const cfg = loadConfig(baseEnv);
  expect(cfg.llmBaseUrl).toBe("https://api.deepseek.com");
  expect(cfg.llmModel).toBe("deepseek-v4-flash");
  expect(cfg.dbPath).toBe("./data/pipeline.sqlite");
  expect(cfg.checkpointPath).toBe("./data/langgraph.sqlite");
  expect(cfg.outputDir).toBe("./output");
  expect(cfg.browserConcurrency).toBe(2);
  expect(cfg.slotConcurrency).toBe(5);
  expect(cfg.proxyUrl).toBeUndefined();
});

test("loadConfig: PROXY_URL 空字符串视为未配置", () => {
  const cfg = loadConfig({ ...baseEnv, PROXY_URL: "" });
  expect(cfg.proxyUrl).toBeUndefined();
});

test("loadConfig: TIMEZONE 必填（所有日期语义以它为准）", () => {
  expect(() => loadConfig({ LLM_API_KEY: "sk-test" })).toThrow(/TIMEZONE/);
});

test("loadConfig: 非法 IANA 时区名抛错", () => {
  expect(() => loadConfig({ ...baseEnv, TIMEZONE: "Mars/Phobos" })).toThrow(/时区/);
  expect(loadConfig(baseEnv).timezone).toBe("Asia/Shanghai");
});

test("assertSystemTimezone: 配置与系统时区一致通过；不一致拒绝运行", () => {
  expect(() => assertSystemTimezone("Asia/Shanghai", "Asia/Shanghai")).not.toThrow();
  expect(() => assertSystemTimezone("UTC", "Asia/Shanghai")).toThrow(/时区校验失败/);
  // 缺省 system 参数 = 系统当前时区：配置与系统一致时必然通过
  const sys = Intl.DateTimeFormat().resolvedOptions().timeZone;
  expect(() => assertSystemTimezone(sys)).not.toThrow();
});
