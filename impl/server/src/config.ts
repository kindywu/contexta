import { z } from "zod";
import { isValidTimezone } from "./engine/config";

/** 每日生成窗口（当日第 N 分钟，0-1439；解析自 DAILY_GENERATE_WINDOW 的 HH:MM-HH:MM）。 */
export interface DailyWindow {
  start: number;
  end: number;
}

/** 服务进程日志目录（与引擎 CLI 一致相对 cwd；deploy 固定 /opt/contexta/server/logs）。 */
export const DEFAULT_LOG_DIR = "logs";

const HHMM_RE = /^\d{2}:\d{2}-\d{2}:\d{2}$/;

/** "HH:MM" → 当日第 N 分钟；非法抛错（仅校验，不在 refine 错误面抛）。 */
function hhmmToMinutes(s: string): number {
  const m = /^(\d{2}):(\d{2})$/.exec(s);
  if (!m) throw new Error(`无效时刻 ${s}（应为 HH:MM）`);
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) throw new Error(`无效时刻 ${s}（HH 00-23，MM 00-59）`);
  return h * 60 + min;
}

/** "HH:MM-HH:MM" → 窗口分钟对；start >= end 抛错。 */
function parseWindow(s: string): DailyWindow {
  const [a, b] = s.split("-") as [string, string];
  const start = hhmmToMinutes(a);
  const end = hhmmToMinutes(b);
  if (start >= end) throw new Error(`窗口结束必须晚于开始: ${s}`);
  return { start, end };
}

/** 分钟 → "HH:MM"。 */
function minutesToHhmm(n: number): string {
  return `${String(Math.floor(n / 60)).padStart(2, "0")}:${String(n % 60).padStart(2, "0")}`;
}

/** 窗口展示格式，如 "08:00-08:15"。 */
export function formatWindow(w: DailyWindow): string {
  return `${minutesToHhmm(w.start)}-${minutesToHhmm(w.end)}`;
}

const windowSchema = z
  .string()
  .regex(HHMM_RE, "格式应为 HH:MM-HH:MM")
  .refine((s) => {
    try {
      const w = parseWindow(s);
      return w.start < w.end;
    } catch {
      return false;
    }
  }, "窗口时刻应合法（HH:MM 00:00-23:59）且开始必须早于结束")
  // 注意顺序：default 必须在 transform 之前——default 喂给 transform 的输入，
  // 放 transform 之后则缺省值被当作"已转换成品"原样透传（字符串直接进 ServerConfig）。
  .default("08:00-08:15")
  .transform((s) => parseWindow(s));

const serverEnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  // 双密钥：App（手机端）与 Admin（Web 管理端）各自签发/验证，互不通用
  JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters"),
  ADMIN_JWT_SECRET: z.string().min(32, "ADMIN_JWT_SECRET must be at least 32 characters"),
  ADMIN_INIT_PASSWORD: z.string().optional().default(""),
  WORD_QUOTA_DAILY: z.coerce.number().int().positive().default(200),
  CACHE_TTL_DAYS: z.coerce.number().int().positive().default(30),
  CACHE_MAX_ROWS: z.coerce.number().int().positive().default(5000),
  DAILY_GENERATE_WINDOW: windowSchema,
  LLM_TIMEOUT_SECS: z.coerce.number().int().positive().default(90),
  REGENERATE_LIMIT: z.coerce.number().int().positive().default(3),
  LLM_API_KEY: z.string().min(1),
  LLM_BASE_URL: z.url().default("https://api.deepseek.com"),
  LLM_MODEL: z.string().default("deepseek-v4-flash"),
  PROXY_URL: z
    .string()
    .optional()
    .default("")
    .transform((s) => (s === "" ? undefined : s)),
  TIMEZONE: z
    .string()
    .min(1)
    .refine(isValidTimezone, "无效的时区名称，应使用 IANA 名（如 Asia/Shanghai、UTC）"),
});

export interface ServerConfig {
  port: number;
  /** App（手机端）令牌密钥：JWT_SECRET。 */
  appJwtSecret: string;
  /** Admin（Web 管理端）令牌密钥：ADMIN_JWT_SECRET。 */
  adminJwtSecret: string;
  adminInitPassword?: string;
  wordQuotaDaily: number;
  cacheTtlDays: number;
  cacheMaxRows: number;
  dailyGenerateWindow: DailyWindow;
  llmTimeoutSecs: number;
  regenerateLimit: number;
  timeZone: string;
  llmApiKey: string;
  llmBaseUrl: string;
  llmModel: string;
  proxyUrl?: string;
}

export function loadServerConfig(
  env: Record<string, string | undefined> = process.env,
): ServerConfig {
  const parsed = serverEnvSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`服务端环境变量配置错误:\n${issues}`);
  }
  const v = parsed.data;
  return {
    port: v.PORT,
    appJwtSecret: v.JWT_SECRET,
    adminJwtSecret: v.ADMIN_JWT_SECRET,
    adminInitPassword: v.ADMIN_INIT_PASSWORD || undefined,
    wordQuotaDaily: v.WORD_QUOTA_DAILY,
    cacheTtlDays: v.CACHE_TTL_DAYS,
    cacheMaxRows: v.CACHE_MAX_ROWS,
    dailyGenerateWindow: v.DAILY_GENERATE_WINDOW,
    llmTimeoutSecs: v.LLM_TIMEOUT_SECS,
    regenerateLimit: v.REGENERATE_LIMIT,
    timeZone: v.TIMEZONE,
    llmApiKey: v.LLM_API_KEY,
    llmBaseUrl: v.LLM_BASE_URL,
    llmModel: v.LLM_MODEL,
    proxyUrl: v.PROXY_URL,
  };
}
