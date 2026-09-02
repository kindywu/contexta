/**
 * 数据导入脚本：把文章管线库（pipeline.sqlite，旧结构含 embedding 列）导入服务端业务库。
 *
 * 契约（设计文档 §5.4）：
 *   1. 备份先行：source 与（若存在）target 均备份到 backupDir，含 -wal/-shm 侧车；
 *      源文件只读不动（本轮绝不在导入中写源库）。
 *   2. cp 源库 → target（不拷 WAL 侧车——源主文件已完整，见验证）。
 *   3. 重建 articles 去 embedding（DROP + RENAME 单事务，外键未强制无约束问题）。
 *   4. ensureSchema（引擎）+ ensureServerSchema（服务端表）。
 *   5. 历史审核行：success 槽 → article_review(status='approved', reviewed_by='import')。
 *   6. 校验（任一失败抛错）：批次数 > 0；articles 行数不变；段落数 = paragraph_count；
 *      review 行数 = articles 行数 = success 槽位数；integrity_check = ok。
 *
 * CLI：bun run tool/import-data.ts -- --source <pipeline.sqlite> --target <contexta.db> [--backup <dir>]
 * 缺省 backup = <target 同目录>/.backup。真实导入由主会话经用户确认后执行，本脚本不自动进行。
 */
import { cpSync, existsSync, mkdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { Database } from "bun:sqlite";
import { ensureServerSchema } from "../src/db";
import { ensureSchema } from "../src/engine/db";

export interface ImportReport {
  /** article_batches 行数（校验：> 0） */
  batches: number;
  /** articles 行数（校验：重建前后一致 = 不丢行） */
  articles: number;
  /** 本脚本写出的历史 approved 行数（校验：= articles 行数 = success 槽位数） */
  reviewRows: number;
  /** 非 success 槽位（rejected/error/pending，仅报告） */
  nonSuccessSlots: number;
  /** PRAGMA integrity_check 结果（校验：= 'ok'） */
  integrity: string;
}

/** 备份文件名时间戳：YYYYMMDD-HHMMSS（本地时区）。 */
function timestamp(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

/** 备份一个库文件：主文件 + 存在的 -wal/-shm 侧车（同名后缀追加到备份名后）。 */
function backupDbFile(dbPath: string, backupDir: string, backupBase: string): void {
  cpSync(dbPath, backupBase);
  for (const suffix of ["-wal", "-shm"]) {
    const sidecar = dbPath + suffix;
    if (existsSync(sidecar)) cpSync(sidecar, backupBase + suffix);
  }
}

function count(db: Database, sql: string): number {
  return (db.query(sql).get() as { c: number }).c;
}

/**
 * 真实导入入口：备份 → 拷贝 → 去 embedding 重建 → 建表 → 历史 approved → 校验。
 * 全程不写源库；可重复运行（每次先备份再整体覆盖 target，失败残留被下次覆盖）。
 */
export async function importPipelineData(
  sourceDb: string,
  targetDb: string,
  backupDir: string,
): Promise<ImportReport> {
  if (!existsSync(sourceDb) || !statSync(sourceDb).isFile()) {
    throw new Error(`源库不存在: ${sourceDb}`);
  }

  const ts = timestamp();
  mkdirSync(backupDir, { recursive: true });
  mkdirSync(dirname(targetDb), { recursive: true });

  // 1. 备份先行：源 与 旧 target（含 -wal/-shm 侧车；源文件只读不动）
  const sourceBackupBase = join(backupDir, `pipeline-source-${ts}.sqlite`);
  backupDbFile(sourceDb, backupDir, sourceBackupBase);
  const targetExisted = existsSync(targetDb);
  if (targetExisted) {
    backupDbFile(targetDb, backupDir, join(backupDir, `target-${ts}.sqlite`));
  }

  // 2. 拷贝源 → target（不拷 WAL 侧车；target 旁残留的是旧 target 的侧车，打开时会被 SQLite
  //    判为不匹配而丢弃——已用 probe 验证，不会把旧帧并进新副本）
  cpSync(sourceDb, targetDb);

  const db = new Database(targetDb);
  try {
    // 3. 打开后先截断残留 -wal（旧 target 侧车；不匹配帧不会应用，checkpoint 仅做清理）
    if (existsSync(targetDb + "-wal")) {
      void db.query("PRAGMA wal_checkpoint(TRUNCATE)").get();
    }

    // 4. 重建 articles 去 embedding（单事务；外键未强制（foreign_keys=0），DROP/ALTER 无约束问题）
    const articlesBefore = count(db, "SELECT count(*) AS c FROM articles");
    db.exec("BEGIN");
    db.exec(`
      CREATE TABLE articles_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL REFERENCES article_batches(id),
        run_date TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        category TEXT NOT NULL,
        path TEXT NOT NULL CHECK (path IN ('A', 'B')),
        source_url TEXT,
        title_en TEXT NOT NULL,
        title_zh TEXT NOT NULL,
        paragraph_count INTEGER NOT NULL,
        markdown_path TEXT NOT NULL,
        thread_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    `);
    db.exec(`
      INSERT INTO articles_new
        (id, batch_id, run_date, difficulty, category, path, source_url,
         title_en, title_zh, paragraph_count, markdown_path, thread_id, created_at)
      SELECT id, batch_id, run_date, difficulty, category, path, source_url,
             title_en, title_zh, paragraph_count, markdown_path, thread_id, created_at
      FROM articles
    `);
    db.exec("DROP TABLE articles");
    db.exec("ALTER TABLE articles_new RENAME TO articles");
    db.exec("COMMIT");

    // 5. 建表：引擎 4 表（INDEX 随 DROP TABLE 一并消失，这里重建）+ 服务端表
    ensureSchema(db);
    ensureServerSchema(db);

    // 6. 历史审核行：success 槽且挂了文章 → approved / import（article_id UNIQUE，OR IGNORE 幂等）
    db.query(`
      INSERT OR IGNORE INTO article_review (article_id, slot_id, status, reviewed_by)
      SELECT s.article_id, s.id, 'approved', 'import'
      FROM batch_slots s
      WHERE s.status = 'success' AND s.article_id IS NOT NULL
    `).run();

    // 7. 校验（任一失败抛错，CLI exit 1）
    const batches = count(db, "SELECT count(*) AS c FROM article_batches");
    const articles = count(db, "SELECT count(*) AS c FROM articles");
    const reviewRows = count(db, "SELECT count(*) AS c FROM article_review");
    const successSlots = count(db, "SELECT count(*) AS c FROM batch_slots WHERE status = 'success' AND article_id IS NOT NULL");
    const nonSuccessSlots = count(db, "SELECT count(*) AS c FROM batch_slots WHERE status != 'success'");
    const badParagraphs = count(
      db,
      `SELECT count(*) AS c FROM articles a
       LEFT JOIN (SELECT article_id, count(*) AS n FROM article_paragraphs GROUP BY article_id) p
         ON p.article_id = a.id
       WHERE coalesce(p.n, 0) != a.paragraph_count`,
    );
    const integrity = (db.query("PRAGMA integrity_check").get() as { integrity_check: string }).integrity_check;

    if (batches === 0) throw new Error(`校验失败: article_batches 为空（0 批）`);
    if (articles !== articlesBefore) {
      throw new Error(`校验失败: articles 行数不一致（重建前 ${articlesBefore} → 重建后 ${articles}，重建丢了行）`);
    }
    if (badParagraphs > 0) {
      throw new Error(`校验失败: ${badParagraphs} 篇段落数 ≠ paragraph_count（LEFT JOIN 对比不一致）`);
    }
    if (reviewRows !== articles) {
      throw new Error(`校验失败: review 行数 ${reviewRows} ≠ articles 行数 ${articles}（success 槽与文章应一一对应）`);
    }
    if (reviewRows !== successSlots) {
      throw new Error(`校验失败: review 行数 ${reviewRows} ≠ success 槽位数 ${successSlots}`);
    }
    if (integrity !== "ok") throw new Error(`校验失败: integrity_check = ${integrity}`);

    return { batches, articles, reviewRows, nonSuccessSlots, integrity };
  } finally {
    db.close();
  }
}

function printUsage(): void {
  console.log(`用法:
  bun run tool/import-data.ts -- --source <pipeline.sqlite> --target <contexta.db> [--backup <dir>]

  --source   文章管线库（只读，不修改；备份为 pipeline-source-<ts>.sqlite + 侧车）
  --target   服务端业务库（已存在则先备份为 target-<ts>.sqlite + 侧车，再整体覆盖）
  --backup   备份目录，缺省 = <target 同目录>/.backup`);
}

function parseArgs(argv: string[]): { source: string; target: string; backup: string } {
  let source = "";
  let target = "";
  let backup = "";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--source") {
      source = argv[++i] ?? "";
    } else if (a === "--target") {
      target = argv[++i] ?? "";
    } else if (a === "--backup") {
      backup = argv[++i] ?? "";
    } else if (a === "--help") {
      printUsage();
      process.exit(0);
    } else {
      throw new Error(`未知参数: ${a}`);
    }
  }
  if (!source) throw new Error("缺少 --source <pipeline.sqlite>（用 --help 查看用法）");
  if (!target) throw new Error("缺少 --target <contexta.db>（用 --help 查看用法）");
  if (!backup) backup = join(dirname(target), ".backup");
  return { source, target, backup };
}

if (import.meta.main) {
  try {
    const { source, target, backup } = parseArgs(process.argv.slice(2));
    const report = await importPipelineData(source, target, backup);
    console.log("导入完成，校验全部通过：");
    console.log(JSON.stringify(report, null, 2));
  } catch (err) {
    console.error(`导入失败: ${(err as Error).message}`);
    process.exit(1);
  }
}
