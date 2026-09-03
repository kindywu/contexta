/**
 * 单轮重试 CLI：bun run retry -- --date 2026-08-29 [--concurrency N] [--log-level debug]
 * 只重跑当日非 success 槽位；「全天重试」= 反复执行本命令（或定时任务）。
 */
import { assertSystemTimezone, loadConfig } from "./config";
import { retryFailedSlots } from "./graph/daily";
import { initLog, log, setLogLevel } from "./graph/log";

function parseArgs(argv: string[]): { date: string; concurrency?: number; logLevel: "info" | "debug" } {
  let date = "";
  let concurrency: number | undefined;
  let logLevel: "info" | "debug" = "info";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--date") {
      const v = argv[i + 1];
      if (v === undefined) throw new Error("--date 需要值");
      if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error("--date 格式应为 YYYY-MM-DD");
      date = v;
      i++;
    } else if (a === "--concurrency") {
      concurrency = Number(argv[i + 1]);
      if (!Number.isInteger(concurrency) || concurrency < 1) throw new Error("--concurrency 必须是 ≥1 整数");
    } else if (a === "--log-level") {
      const l = argv[i + 1]!;
      if (l === "info" || l === "debug") logLevel = l;
      else throw new Error(`--log-level 只支持 info|debug，收到 ${l}`);
    }
  }
  if (!date) throw new Error("缺少 --date <YYYY-MM-DD>");
  return { date, concurrency, logLevel };
}

async function main() {
  const cfg = loadConfig();
  assertSystemTimezone(cfg.timezone); // 启动校验：配置时区与系统时区不一致 → 拒绝运行
  const logFile = initLog("logs", cfg.timezone);
  const { date, concurrency, logLevel } = parseArgs(process.argv.slice(2));
  setLogLevel(logLevel);
  log(`运行日志: ${logFile}`);
  const result = await retryFailedSlots({ runDate: date, concurrency, config: cfg });
  log(`[retry] 结束 ${JSON.stringify(result)}`);
  console.log(`retry result: ${JSON.stringify(result)}`);
}

main().catch((err) => {
  log(`重试失败: ${err instanceof Error ? err.message : String(err)}`);
  console.error("重试失败:", err);
  process.exit(1);
});
