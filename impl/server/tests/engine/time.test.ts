import { expect, test } from "bun:test";
import { localDate, localFileStamp, localTimestamp } from "../../src/engine/utils/time";

// 固定时刻：2026-08-29T17:30:00.123Z —— 上海 = 2026-08-30 01:30:00.123, 纽约 = 2026-08-29 13:30（EDT）
const now = new Date("2026-08-29T17:30:00.123Z");

test("localDate: 按配置时区取当天日期（跨日边界以配置时区为准）", () => {
  expect(localDate("Asia/Shanghai", now)).toBe("2026-08-30");
  expect(localDate("UTC", now)).toBe("2026-08-29");
  expect(localDate("America/New_York", now)).toBe("2026-08-29");
});

test("localDate: 上海午夜刚过 1 分钟 → 已翻到明天", () => {
  const midnight = new Date("2026-08-29T16:01:00Z"); // 上海 2026-08-30 00:01
  expect(localDate("Asia/Shanghai", midnight)).toBe("2026-08-30");
  expect(localDate("UTC", midnight)).toBe("2026-08-29");
});

test("localTimestamp: HH:MM:SS.mmm 为配置时区本地时刻", () => {
  expect(localTimestamp("Asia/Shanghai", now)).toBe("01:30:00.123");
  expect(localTimestamp("UTC", now)).toBe("17:30:00.123");
  expect(localTimestamp("America/New_York", now)).toBe("13:30:00.123");
});

test("localFileStamp: 日志文件命名用本地日期时间（无 UTC 的 Z 后缀）", () => {
  expect(localFileStamp("Asia/Shanghai", now)).toBe("2026-08-30T01-30-00-123");
  expect(localFileStamp("UTC", now)).toBe("2026-08-29T17-30-00-123");
});
