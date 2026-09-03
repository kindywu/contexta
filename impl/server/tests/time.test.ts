import { expect, test } from "bun:test";
import { todayStartMillis } from "../src/time";

// 固定时刻：2026-08-29T17:30:00.123Z —— 上海 = 2026-08-30，纽约/UTC = 2026-08-29（跨日边界以配置时区为准）
const now = new Date("2026-08-29T17:30:00.123Z");

test("todayStartMillis: 返回配置时区当天的当地零点", () => {
  // 上海当天是 08-30，纽约/UTC 是 08-29；零点 = 该日（系统本地时区）午夜的 epoch millis
  expect(todayStartMillis("Asia/Shanghai", now)).toBe(new Date(2026, 7, 30).getTime());
  expect(todayStartMillis("America/New_York", now)).toBe(new Date(2026, 7, 29).getTime());
  expect(todayStartMillis("UTC", now)).toBe(new Date(2026, 7, 29).getTime());
});

test("todayStartMillis: 结果是当天 0 点（无时分秒）", () => {
  const ms = todayStartMillis("Asia/Shanghai", now);
  const d = new Date(ms);
  expect(d.getHours()).toBe(0);
  expect(d.getMinutes()).toBe(0);
  expect(d.getSeconds()).toBe(0);
  expect(d.getMilliseconds()).toBe(0);
});

test("todayStartMillis: 缺省 timeZone 沿用系统时区", () => {
  const ms = todayStartMillis(undefined, now); // 不抛错，返回一个整数零点
  expect(Number.isInteger(ms)).toBe(true);
});

test("todayStartMillis: 上海午夜刚过 1 分钟 → 已翻到明天", () => {
  const midnight = new Date("2026-08-29T16:01:00Z"); // 上海 2026-08-30 00:01
  expect(todayStartMillis("Asia/Shanghai", midnight)).toBe(new Date(2026, 7, 30).getTime());
  expect(todayStartMillis("UTC", midnight)).toBe(new Date(2026, 7, 29).getTime());
});
