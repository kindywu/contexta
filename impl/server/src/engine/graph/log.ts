/**
 * 极简运行日志：
 * - CLI 默认（prefix="run"，echo=true）：写 logs/run-<本地时间戳>.log（同时打到终端），
 *   每次运行一个新文件——与旧行为一致；
 * - 服务进程（prefix="daily"，echo=false）：写 logs/daily-<本地日期>.log（按天轮转，
 *   跨日自动换文件），只进文件不进 web stdout——生成日志与 Web 服务日志互不干扰。
 * 图表节点逐节点记一行，带时间戳与耗时——出问题（死循环、LLM 故障、校验拒绝）
 * 时按文件回放就能定位到步骤。
 * 时间戳一律取配置时区（TIMEZONE）的本地时刻，见 src/utils/time.ts。
 */
import { appendFileSync, mkdirSync, readdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { localDate, localFileStamp, localTimestamp } from "../utils/time";

let logDir = "";
let logPath = "";
let logLevel: LogLevel = "info";
let logTimeZone: string | undefined;
let logPrefix = "run";
let logEcho = true;

/** 日志等级：debug 显示 prompt 全文等细节，info 只记摘要行。 */
export type LogLevel = "info" | "debug";

/** 设置日志等级（命令行 --log-level 传入；默认 info）。 */
export function setLogLevel(level: LogLevel): void {
  logLevel = level;
}

export interface InitLogOpts {
  /** 文件名前缀：缺省 "run"（run-<时间戳>.log，每次运行一个新文件）；
   *  "daily" → daily-<当天日期>.log，按天轮转。 */
  prefix?: string;
  /** 是否同时输出终端：缺省 true；服务进程传 false（生成日志只进文件，不污染 web stdout）。 */
  echo?: boolean;
}

/** 初始化日志文件（入口启动时调用一次）；timeZone 缺省取系统时区。返回文件路径。 */
export function initLog(dir: string, timeZone?: string, opts: InitLogOpts = {}): string {
  mkdirSync(dir, { recursive: true });
  logTimeZone = timeZone;
  logPrefix = opts.prefix ?? "run";
  logEcho = opts.echo ?? true;
  logDir = dir;
  logPath = resolveLogPath();
  return logPath;
}

/** 当前模式下日志文件路径（daily 模式 = 今天日期对应的文件）。 */
function resolveLogPath(): string {
  return logPrefix === "daily"
    ? join(logDir, `daily-${localDate(logTimeZone)}.log`)
    : join(logDir, `run-${localFileStamp(logTimeZone)}.log`);
}

/** 当前日志文件路径（未初始化返回空串）。 */
export function logFilePath(): string {
  return logPath;
}

/** 重定向全局 log() 的目标文件（replay 等工具就地切换到自己的日志文件）。 */
export function redirectLogFile(file: string): void {
  logPath = file;
  logDir = ""; // 退出 daily 按日解析，落回显式路径
}

const ts = () => localTimestamp(logTimeZone);

export function log(msg: string, level: LogLevel = "info"): void {
  if (level === "debug" && logLevel !== "debug") return; // 低于当前阈值不输出
  const line = `[${ts()}] ${msg}`;
  if (logEcho) console.log(line);
  if (logPath) {
    try {
      // daily 前缀：每次写入按当天日期重解析（跨日自然轮转到新文件）
      const file =
        logPrefix === "daily" && logDir
          ? join(logDir, `daily-${localDate(logTimeZone)}.log`)
          : logPath;
      appendFileSync(file, line + "\n");
    } catch {
      // 日志写入失败不阻塞主流程
    }
  }
}

/**
 * 轮转清理：删除目录下文件名含 YYYY-MM-DD 且日期早于保留窗（keepDays 天，含今天）
 * 的 *.log；无日期文件不动。返回删除数。目录不存在/不可读返回 0。
 */
export function cleanupOldLogs(dir: string, keepDays = 7, timeZone?: string): number {
  let removed = 0;
  let names: string[];
  try {
    names = readdirSync(dir).filter((n) => n.endsWith(".log"));
  } catch {
    return 0;
  }
  const [y, m, d] = localDate(timeZone).split("-").map(Number);
  const limit = localDate(timeZone, new Date(y, m - 1, d - (keepDays - 1)));
  for (const name of names) {
    const match = /(\d{4})-(\d{2})-(\d{2})/.exec(name);
    if (!match) continue;
    const fileDate = `${match[1]}-${match[2]}-${match[3]}`;
    if (fileDate < limit) {
      try {
        unlinkSync(join(dir, name));
        removed++;
      } catch {
        // 删除失败（权限/竞态）不阻塞
      }
    }
  }
  return removed;
}
