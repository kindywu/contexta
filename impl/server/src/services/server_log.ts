// src/services/server_log.ts
// 服务端（Web）日志：logs/ 目录下 server-<本地日期>.log（按天轮转）+ 同步输出 stdout
// （journald / 终端仍可见）。与引擎生成日志（graph/log.ts 的 daily 前缀，只进文件）分离，
// 互不干扰。未 init 时仅 console（启动早期 config 失败路径可用）。
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { localDate, localTimestamp } from "../engine/utils/time";

let logDir = "";
let logTimeZone: string | undefined;

/** 初始化服务端日志目录（main 启动时调用一次；重复调用切换目标目录）。 */
export function initServerLog(dir: string, timeZone?: string): void {
  mkdirSync(dir, { recursive: true });
  logDir = dir;
  logTimeZone = timeZone;
}

function errText(err: unknown): string {
  return err instanceof Error ? (err.stack ?? err.message) : String(err);
}

/** 追加一行到指定文件（未 init 或写入失败静默跳过）。 */
function write(file: string, line: string): void {
  if (!logDir) return;
  try {
    appendFileSync(join(logDir, file), line + "\n");
  } catch {
    // 日志写入失败不阻塞主流程
  }
}

const stamp = () => localTimestamp(logTimeZone);

export function serverLog(msg: string): void {
  const line = `[${stamp()}] ${msg}`;
  console.log(line);
  write(`server-${localDate(logTimeZone)}.log`, line);
}

export function serverWarn(msg: string, err?: unknown): void {
  const line = `[${stamp()}] ${msg}${err === undefined ? "" : ` ${errText(err)}`}`;
  console.warn(line);
  write(`server-${localDate(logTimeZone)}.log`, line);
}

export function serverError(msg: string, err?: unknown): void {
  const line = `[${stamp()}] ${msg}${err === undefined ? "" : ` ${errText(err)}`}`;
  console.error(line);
  write(`server-${localDate(logTimeZone)}.log`, line);
}

/** 访问日志通道：app = 手机端（App 请求），web = Web 管理端（/admin 与 /api/admin/*）。 */
export type AccessChannel = "app" | "web";

/** 通道 → 日志文件名前缀与 console 颜色（app 青色 / web 品红，正文同色仅控制台染）。 */
const CHANNEL_FILE_PREFIX: Record<AccessChannel, string> = { app: "app", web: "admin" };
const CHANNEL_COLOR: Record<AccessChannel, string> = { app: "\x1b[36m", web: "\x1b[35m" };
const RESET = "\x1b[0m";

/** 访问日志：按通道写独立文件（app-<今天>.log / admin-<今天>.log），控制台带颜色区分。 */
export function accessLog(channel: AccessChannel, msg: string): void {
  const line = `[${stamp()}] ${msg}`;
  console.log(`${CHANNEL_COLOR[channel]}${line}${RESET}`);
  write(`${CHANNEL_FILE_PREFIX[channel]}-${localDate(logTimeZone)}.log`, line);
}
