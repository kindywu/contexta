import { z } from "zod";

/**
 * 配置来源：
 * - LLM/路径/网络等运行参数从环境变量（.env 由 Bun 自动加载，无需 dotenv）读取；
 * - 权威站点配置见 sites.config.ts（sites.yaml 不再由本模块解析）。
 * 完整变量清单见 .env.example。
 */

/** 校验 IANA 时区名（如 Asia/Shanghai、UTC），非法返回 false。 */
export function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

const envSchema = z.object({
  LLM_API_KEY: z.string().min(1),
  LLM_BASE_URL: z.url().default("https://api.deepseek.com"),
  LLM_MODEL: z.string().default("deepseek-v4-flash"),
  /** 所有日期语义（"今天"、日志时间戳、日志文件名）以该时区为准；必填且启动时须与系统时区一致 */
  TIMEZONE: z
    .string()
    .min(1)
    .refine(isValidTimezone, "无效的时区名称，应使用 IANA 名（如 Asia/Shanghai、UTC）"),
  DB_PATH: z.string().default("./data/pipeline.sqlite"),
  CHECKPOINT_PATH: z.string().default("./data/langgraph.sqlite"),
  OUTPUT_DIR: z.string().default("./output"),
  BROWSER_CONCURRENCY: z.coerce.number().int().positive().default(2),
  SLOT_CONCURRENCY: z.coerce.number().int().positive().default(5),
  PROXY_URL: z
    .string()
    .optional()
    .default("")
    .transform((s) => (s === "" ? undefined : s)),
});

export interface AppConfig {
  /** 必填：所有 LLM 调用共用的 API key */
  llmApiKey: string;
  /** Anthropic-compatible Messages API 端点（默认 DeepSeek） */
  llmBaseUrl: string;
  llmModel: string;
  /** 日期语义时区（IANA 名）；启动时校验与系统当前时区一致，不一致拒绝运行 */
  timezone: string;
  dbPath: string;
  /** LangGraph checkpoint 独立存储（与业务库分开） */
  checkpointPath: string;
  outputDir: string;
  browserConcurrency: number;
  slotConcurrency: number;
  /** 出站 HTTP 代理（http:// 形式），未配置则不代理 */
  proxyUrl?: string;
}

export function loadConfig(
  env: Record<string, string | undefined> = process.env,
): AppConfig {
  const picked = {
    LLM_API_KEY: env.LLM_API_KEY,
    LLM_BASE_URL: env.LLM_BASE_URL,
    LLM_MODEL: env.LLM_MODEL,
    TIMEZONE: env.TIMEZONE,
    DB_PATH: env.DB_PATH,
    CHECKPOINT_PATH: env.CHECKPOINT_PATH,
    OUTPUT_DIR: env.OUTPUT_DIR,
    BROWSER_CONCURRENCY: env.BROWSER_CONCURRENCY,
    SLOT_CONCURRENCY: env.SLOT_CONCURRENCY,
    PROXY_URL: env.PROXY_URL,
  };

  const parsed = envSchema.safeParse(picked);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    const hint = picked.LLM_API_KEY
      ? ""
      : "\n提示：请先用 `cp .env.example .env` 生成配置并填入 LLM_API_KEY。";
    throw new Error(`环境变量配置错误:\n${issues}${hint}`);
  }
  const v = parsed.data;

  return {
    llmApiKey: v.LLM_API_KEY,
    llmBaseUrl: v.LLM_BASE_URL,
    llmModel: v.LLM_MODEL,
    timezone: v.TIMEZONE,
    dbPath: v.DB_PATH,
    checkpointPath: v.CHECKPOINT_PATH,
    outputDir: v.OUTPUT_DIR,
    browserConcurrency: v.BROWSER_CONCURRENCY,
    slotConcurrency: v.SLOT_CONCURRENCY,
    proxyUrl: v.PROXY_URL,
  };
}

/**
 * 启动校验：配置的 TIMEZONE 必须与系统当前时区一致。
 * 所有日期语义（"今天"、日志时间戳、日志文件名）以配置时区为准——若配置时区与
 * 系统不一致，本地时刻的定义就会漂移（如"今天"变成昨天/明天），因此不通过即拒绝运行。
 * systemTimeZone 参数缺省取系统值，测试可注入。
 */
export function assertSystemTimezone(
  timezone: string,
  systemTimeZone: string = Intl.DateTimeFormat().resolvedOptions().timeZone,
): void {
  if (timezone !== systemTimeZone) {
    throw new Error(
      `时区校验失败：配置 TIMEZONE=${timezone}，系统当前时区=${systemTimeZone}。` +
        `所有日期以配置时区为准，两者必须一致才能运行（请修改 .env 的 TIMEZONE 或系统的时区后重试）。`,
    );
  }
}
