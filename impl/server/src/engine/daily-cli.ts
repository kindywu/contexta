/**
 * 每日生成 CLI：bun run daily -- --date 2026-08-29 [--log-level debug]
 * 落库（批次/槽位/文章）、去重上下文、失败槽位重试由 retry 命令负责。
 */
import { assertSystemTimezone, loadConfig } from "./config";
import { generateDailyArticles } from "./graph/daily";
import { initLog, log, setLogLevel } from "./graph/log";
import { localDate } from "./utils/time";

function parseArgs(argv: string[], timezone: string): { date: string; logLevel: "info" | "debug" } {
  let date = localDate(timezone); // "今天"按配置时区取，跨日边界以配置时区为准
  let logLevel: "info" | "debug" = "info";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--date") {
      const v = argv[i + 1];
      if (v === undefined) throw new Error("--date 需要值");
      if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error("--date 格式应为 YYYY-MM-DD");
      date = v;
      i++;
    } else if (a === "--log-level") {
      const l = argv[i + 1]!;
      if (l === "info" || l === "debug") logLevel = l;
      else throw new Error(`--log-level 只支持 info|debug，收到 ${l}`);
    }
  }
  return { date, logLevel };
}

async function main() {
  const cfg = loadConfig();
  assertSystemTimezone(cfg.timezone); // 启动校验：配置时区与系统时区不一致 → 拒绝运行
  const logFile = initLog("logs", cfg.timezone);
  const { date, logLevel } = parseArgs(process.argv.slice(2), cfg.timezone);
  setLogLevel(logLevel);
  log(`运行日志: ${logFile}`);
  const day = await generateDailyArticles({ runDate: date, config: cfg });
  log(`[daily] 结束 date=${date} total=${day.total} summary=${JSON.stringify(day.summary)}`);
  console.log(`summary: ${JSON.stringify(day.summary)}`);
}

main().catch((err) => {
  log(`每日运行失败: ${err instanceof Error ? err.message : String(err)}`);
  console.error("每日运行失败:", err);
  process.exit(1);
});
