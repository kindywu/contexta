import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { assertSystemTimezone, loadConfig } from "./config";
import { generateArticle } from "./graph";
import { initLog, log, setLogLevel } from "./graph/log";
import type { Difficulty } from "./schema";
import { renderMarkdown } from "./render";
import { localDate } from "./utils/time";

/**
 * 入口：`bun run start` 真实跑一次文章生成流程。
 *
 * 流程：按 difficulty 随机选类别 → (news/expository) 抓权威来源 → 抽事实卡
 * → 生成双语文章 → LLM 安全校验 → 重试/通过；产出 Markdown 写到 output/。
 *
 * 可执行 LangGraph 断点续跑：如果上次执行因网络/LLM 故障中断，再次用相同
 * --resume <id> 续跑会从 checkpoint 恢复（详见 src/graph/checkpointer.ts）。
 *
 * 用法：
 *   bun run start                       # MEDIUM、今天
 *   bun run start -- --difficulty HIGH  # 指定难度
 *   bun run start -- --date 2026-08-28  # 指定日期
 *   bun run start -- --resume <id>      # 断点续跑（忽略 --date/--difficulty 输入）
 *   bun run start -- --log-level debug  # 日志记录 LLM 请求的完整 prompt（默认 info 只记摘要）
 */


function parseArgs(argv: string[], timezone: string): {
  difficulty: Difficulty;
  date: string;
  resume?: string;
  logLevel: "info" | "debug";
} {
  const out: {
    difficulty?: Difficulty;
    date?: string;
    resume?: string;
    logLevel?: "info" | "debug";
  } = {};
  const args = argv.slice(2);
  const validDifficulty = new Set<Difficulty>(["LOW", "MEDIUM", "HIGH"]);
  const validLogLevel = new Set(["info", "debug"]);

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    const val = args[i + 1];

    if (arg === "--difficulty" && val && validDifficulty.has(val as Difficulty)) {
      out.difficulty = val as Difficulty;
      i++;
    } else if (arg === "--date" && val) {
      out.date = val;
      i++;
    } else if (arg === "--resume") {
      out.resume = val;
    } else if (arg === "--log-level" && val && validLogLevel.has(val)) {
      out.logLevel = val as "info" | "debug";
      i++;
    }
  }

  return {
    difficulty: out.difficulty ?? "MEDIUM",
    date: out.date ?? localDate(timezone), // "今天"按配置时区取
    resume: out.resume,
    logLevel: out.logLevel ?? "info"
  };
}



async function main() {
  const cfg = loadConfig();
  assertSystemTimezone(cfg.timezone); // 启动校验：配置时区与系统时区不一致 → 拒绝运行
  const logFile = initLog("logs", cfg.timezone);
  log(`运行日志: ${logFile}`);

  const { difficulty, date, resume, logLevel } = parseArgs(process.argv, cfg.timezone);
  setLogLevel(logLevel);
  const runDate = date;

  const threadId = resume;
  log(`threadId: ${threadId} (断点续跑加 --resume --thread-id xxx)`);

  const targetRunDate = resume ? "" : runDate;
  const result = await generateArticle({
    runDate: targetRunDate,
    difficulty,
    threadId,
  });


  if (result.outcome !== "success") {
    const msg = "reason" in result ? result.reason : result.message;
    log(`结果 [${result.outcome}]: ${msg}`);
    console.error(`生成失败 [${result.outcome}]: ${msg}`);
    process.exit(1);
  }
  const { article } = result;
  log(`结果 [success] ${article.category}/${article.path} ${article.titleEn}`);

  // 落盘 Markdown，文件名对齐数据库 markdown_path 风格 run_date-category-ts
  await mkdir(cfg.outputDir, { recursive: true });
  const file = join(
    cfg.outputDir,
    `${article.runDate}-${article.category}-${Date.now()}.md`,
  );
  await Bun.write(file, renderMarkdown(article));
  log(`已保存: ${file}`);
}


main().catch((err) => {
  console.error("Pipeline 运行失败:", err);
  process.exit(1);
});
