/**
 * 时区统一工具：所有日期语义（"今天"、日志时间戳、日志文件名时间戳）以配置时区
 * （TIMEZONE，启动时校验与系统一致）为准——不用 UTC 时刻，避免跨日边界漂移。
 * timeZone 缺省时沿用系统时区（Intl 默认行为）；now 参数供测试注入固定时刻。
 */

type Parts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

function partsOf(now: Date, timeZone?: string): Parts {
  const base: Intl.DateTimeFormatOptions = {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23", // 午夜输出 00 而非 24
  };
  const fmt = new Intl.DateTimeFormat("en-US", timeZone ? { ...base, timeZone } : base);
  const map: Partial<Record<string, number>> = {};
  for (const p of fmt.formatToParts(now)) {
    if (p.type !== "literal") map[p.type] = Number(p.value);
  }
  return {
    year: map.year!,
    month: map.month!,
    day: map.day!,
    hour: map.hour!,
    minute: map.minute!,
    second: map.second!,
  };
}

const pad = (n: number) => String(n).padStart(2, "0");

/** 配置时区当天的本地日期 YYYY-MM-DD（"今天是几号"的唯一口径）。 */
export function localDate(timeZone?: string, now: Date = new Date()): string {
  const p = partsOf(now, timeZone);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
}

/** 配置时区的本地时刻 HH:MM:SS.mmm（日志行时间戳；毫秒与时区无关）。 */
export function localTimestamp(timeZone?: string, now: Date = new Date()): string {
  const p = partsOf(now, timeZone);
  const ms = String(now.getUTCMilliseconds()).padStart(3, "0");
  return `${pad(p.hour)}:${pad(p.minute)}:${pad(p.second)}.${ms}`;
}

/** 本地日期时间戳，供日志文件名使用（无 UTC 的 Z 后缀）：CCYY-MM-DDTHH-MM-SS-mmm。 */
export function localFileStamp(timeZone?: string, now: Date = new Date()): string {
  return `${localDate(timeZone, now)}T${localTimestamp(timeZone, now).replace(/[:.]/g, "-")}`;
}
