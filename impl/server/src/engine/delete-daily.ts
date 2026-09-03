/**
 * 删除某日数据 CLI：bun run delete-daily -- --date 2026-08-29 --yes [--log-level debug]
 * 清理范围：业务库当日批次/槽位/文章/段落 + 该日线程的 LangGraph 检查点（langgraph.sqlite）。
 * 必须有 --yes 才执行实际删除（防误删）；否则打印待删概览并以非零码退出。
 */
import { Database } from "bun:sqlite";
import { assertSystemTimezone, loadConfig } from "./config";
import { deleteDailyData, ensureSchema, getBatch, listSlots } from "./db";
import { BunSqliteCheckpointer } from "./graph/checkpointer";
import { initLog, log, setLogLevel } from "./graph/log";

function parseArgs(argv: string[]): { date: string; yes: boolean; logLevel: "info" | "debug" } {
  let date = "";
  let yes = false;
  let logLevel: "info" | "debug" = "info";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--date") {
      const v = argv[i + 1];
      if (v === undefined) throw new Error("--date 需要值");
      if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error("--date 格式应为 YYYY-MM-DD");
      date = v;
      i++;
    } else if (a === "--yes") {
      yes = true;
    } else if (a === "--log-level") {
      const l = argv[i + 1]!;
      if (l === "info" || l === "debug") logLevel = l;
      else throw new Error(`--log-level 只支持 info|debug，收到 ${l}`);
    }
  }
  if (!date) throw new Error("缺少 --date <YYYY-MM-DD>");
  return { date, yes, logLevel };
}

function count(db: Database, sql: string, ...args: string[]): number {
  return (db.query(sql).get(...args) as { c: number }).c;
}

/** 检查点库中属于该日的线程数（thread_id 前缀 daily-<date>-，含旧格式 <slot>-<attempt>）。 */
async function countCpThreads(cp: BunSqliteCheckpointer, date: string): Promise<number> {
  const prefix = `daily-${date}-`;
  let n = 0;
  for await (const t of cp.list({ configurable: {} })) {
    if (t.config.configurable?.thread_id?.startsWith(prefix)) n++;
  }
  return n;
}

async function main() {
  const cfg = loadConfig();
  assertSystemTimezone(cfg.timezone); // 启动校验：配置时区与系统时区不一致 → 拒绝运行
  const logFile = initLog("logs", cfg.timezone);
  const { date, yes, logLevel } = parseArgs(process.argv.slice(2));
  setLogLevel(logLevel);
  log(`运行日志: ${logFile}`);

  const db = new Database(cfg.dbPath, { create: true });
  ensureSchema(db);
  const cp = new BunSqliteCheckpointer(cfg.checkpointPath);
  const preview = {
    batches: getBatch(db, date) ? 1 : 0,
    slots: listSlots(db, date).length,
    articles: count(db, "SELECT count(*) AS c FROM articles WHERE run_date = ?", date),
    paragraphs: count(
      db,
      "SELECT count(*) AS c FROM article_paragraphs WHERE article_id IN (SELECT id FROM articles WHERE run_date = ?)",
      date,
    ),
    checkpoints: await countCpThreads(cp, date),
  };

  if (!yes) {
    const msg = `模拟删除（未执行）：date=${date} batches=${preview.batches} slots=${preview.slots} articles=${preview.articles} paragraphs=${preview.paragraphs} checkpoints=${preview.checkpoints}；确认请加 --yes`;
    log(`[delete-daily] ${msg}`);
    console.log(msg);
    process.exit(1);
  }

  const deleted = deleteDailyData(db, date);
  const cpDeleted = cp.deleteThreadsByDate(date);
  const summary = { date, ...deleted, checkpoints: cpDeleted.checkpoints, cpWrites: cpDeleted.writes };
  log(`[delete-daily] 结束 ${JSON.stringify(summary)}`);
  console.log(`deleted: ${JSON.stringify(summary)}`);
}

main().catch((err) => {
  log(`删除失败: ${err instanceof Error ? err.message : String(err)}`);
  console.error("删除失败:", err);
  process.exit(1);
});
