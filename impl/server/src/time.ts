import { localDate } from "./engine/utils/time";

/**
 * 配置时区当地零点的 epoch millis（assertSystemTimezone 保证系统时区 == 配置时区，
 * 故 new Date(y, m-1, d) 在系统本地构造即为配置时区零点）。
 */
export function todayStartMillis(timeZone?: string, now: Date = new Date()): number {
  const d = localDate(timeZone, now);
  const [y, m, day] = d.split("-").map(Number);
  return new Date(y, m - 1, day).getTime();
}
