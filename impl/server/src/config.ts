import { z } from "zod";
import { isValidTimezone } from "./engine/config";

const serverEnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  JWT_SECRET: z.string().min(32, "JWT_SECRET must be at least 32 characters"),
  ADMIN_INIT_PASSWORD: z.string().optional().default(""),
  WORD_QUOTA_DAILY: z.coerce.number().int().positive().default(200),
  CACHE_TTL_DAYS: z.coerce.number().int().positive().default(30),
  CACHE_MAX_ROWS: z.coerce.number().int().positive().default(5000),
  DAILY_GENERATE_HOUR: z.coerce.number().int().min(0).max(23).default(3),
  LLM_TIMEOUT_SECS: z.coerce.number().int().positive().default(90),
  REGENERATE_LIMIT: z.coerce.number().int().positive().default(3),
  TIMEZONE: z
    .string()
    .min(1)
    .refine(isValidTimezone, "无效的时区名称，应使用 IANA 名（如 Asia/Shanghai、UTC）"),
});

export interface ServerConfig {
  port: number;
  jwtSecret: string;
  adminInitPassword?: string;
  wordQuotaDaily: number;
  cacheTtlDays: number;
  cacheMaxRows: number;
  dailyGenerateHour: number;
  llmTimeoutSecs: number;
  regenerateLimit: number;
  timeZone: string;
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
    jwtSecret: v.JWT_SECRET,
    adminInitPassword: v.ADMIN_INIT_PASSWORD || undefined,
    wordQuotaDaily: v.WORD_QUOTA_DAILY,
    cacheTtlDays: v.CACHE_TTL_DAYS,
    cacheMaxRows: v.CACHE_MAX_ROWS,
    dailyGenerateHour: v.DAILY_GENERATE_HOUR,
    llmTimeoutSecs: v.LLM_TIMEOUT_SECS,
    regenerateLimit: v.REGENERATE_LIMIT,
    timeZone: v.TIMEZONE,
  };
}
