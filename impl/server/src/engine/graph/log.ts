/**
 * 极简运行日志：写入 logs/run-<本地时间戳>.log（同时打到终端）。
 * 图表节点逐节点记一行，带时间戳与耗时——出问题（死循环、LLM 故障、校验拒绝）
 * 时按文件回放就能定位到步骤。
 * 时间戳一律取配置时区（TIMEZONE）的本地时刻，见 src/utils/time.ts。
 */
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { localFileStamp, localTimestamp } from "../utils/time";

let logPath = "";
let logLevel: LogLevel = "info";
let logTimeZone: string | undefined;

/** 日志等级：debug 显示 prompt 全文等细节，info 只记摘要行。 */
export type LogLevel = "info" | "debug";

/** 设置日志等级（命令行 --log-level 传入；默认 info）。 */
export function setLogLevel(level: LogLevel): void {
  logLevel = level;
}

/** 初始化日志文件（main 启动时调用一次）；timeZone 缺省取系统时区。返回文件路径。 */
export function initLog(dir: string, timeZone?: string): string {
  mkdirSync(dir, { recursive: true });
  logTimeZone = timeZone;
  logPath = join(dir, `run-${localFileStamp(logTimeZone)}.log`);
  return logPath;
}

/** 当前日志文件路径（未初始化返回空串）。 */
export function logFilePath(): string {
  return logPath;
}

/** 重定向全局 log() 的目标文件（replay 等工具就地切换到自己的日志文件）。 */
export function redirectLogFile(file: string): void {
  logPath = file;
}

const ts = () => localTimestamp(logTimeZone);

export function log(msg: string, level: LogLevel = "info"): void {
  if (level === "debug" && logLevel !== "debug") return; // 低于当前阈值不输出
  const line = `[${ts()}] ${msg}`;
  console.log(line);
  if (logPath) {
    try {
      appendFileSync(logPath, line + "\n");
    } catch {
      // 日志写入失败不阻塞主流程
    }
  }
}
