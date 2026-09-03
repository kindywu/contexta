import { Database } from "bun:sqlite";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { loadConfig, type AppConfig } from "../config";
import type { LLM } from "../llm";
import { Difficulty } from "../schema";
import { runPool } from "../utils/pool";
import {
  createBatchAndSlots,
  ensureSchema,
  finalizeBatch,
  getBatch,
  insertArticleWithParagraphs,
  listRecentArticles,
  listSlots,
  writeSlotResult,
  type BatchRow,
  type SlotRow,
  type SlotStatus,
} from "../db";
import { BunSqliteCheckpointer } from "./checkpointer";
import { generateArticle, toResult, type ArticleResult } from "./index";
import { ArticleGenState, GeneratedArticle } from "./state";
import { log } from "./log";
import { renderMarkdown } from "../render";
import { byCategory } from "../sites.config";

/** 缺省每日计划：每个难度 5 篇，共 15 篇/天。 */
export const DEFAULT_DAILY_PLAN: Record<Difficulty, number> = {
  LOW: 5,
  MEDIUM: 5,
  HIGH: 5,
};

/** 每天生成计划：难度 → 篇数（个数 ≥ 0 的整数，0 或未填 = 该难度不生成）。 */
export type DailyPlan = Partial<Record<Difficulty, number>>;

/** 单个槽位（每篇一槽）的执行结果。 */
export interface DaySlotResult {
  /** 槽位序号（0 起，按 LOW → MEDIUM → HIGH 展开序）。 */
  slot: number;
  difficulty: Difficulty;
  result: ArticleResult;
}

export interface DayResult {
  runDate: string;
  total: number;
  /** 按 slot 顺序展开的所有槽位结果。 */
  results: DaySlotResult[];
  summary: {
    success: number;
    rejected: number;
    error: number;
  };
}

export interface GenerateDailyArticlesArgs {
  runDate: string;
  /** 难度 → 篇数；缺省 DEFAULT_DAILY_PLAN（5/5/5）。 */
  plan?: DailyPlan;
  /** 并发槽位数上限；缺省取 cfg.slotConcurrency（SLOT_CONCURRENCY，默认 5）。 */
  concurrency?: number;
  config?: AppConfig;
  llm?: LLM;
}

/**
 * 槽位线程 id：首试 = daily-<runDate>-<slotIndex>；带增量后缀的旧格式
 * （daily-<runDate>-<slotIndex>-<attempt>）为历史数据保留——当前图内自动
 * 重试同线程进行，retry CLI 不再换新 id。
 */
export function slotThreadId(runDate: string, slotIndex: number, attempt: number): string {
  return attempt <= 1 ? `daily-${runDate}-${slotIndex}` : `daily-${runDate}-${slotIndex}-${attempt}`;
}

/** §4.3 尝试明细日志行：slot/attempt/thread/outcome/reason 必带字段。 */
export function slotAttemptLog(
  prefix: string,
  slot: SlotRow,
  details: { attempt: number; threadId: string; outcome: string; reason?: string; started: boolean },
): string {
  const action = details.started ? "开始" : "完成";
  const reason = details.reason ? ` reason=${details.reason}` : "";
  return `${prefix} slot ${slot.slotIndex} [${slot.difficulty}] ${action} attempt=${details.attempt} thread=${details.threadId} outcome=${details.outcome}${reason}`;
}

/**
 * 把计划展开为槽位列表：[LOW × n, MEDIUM × n, HIGH × n]（计数为 0 的难度跳过）。
 * 纯函数：供生成函数与测试共用。计数非法（负数/非整数）抛错；全 0 视为
 * 调用方错误也抛错（要默认计划就直接不传 plan）。
 */
export function expandPlan(plan: DailyPlan): { difficulty: Difficulty; slot: number }[] {
  const slots: { difficulty: Difficulty; slot: number }[] = [];
  let slot = 0;
  for (const difficulty of ["LOW", "MEDIUM", "HIGH"] as const) {
    const count = plan[difficulty] ?? 0;
    if (!Number.isInteger(count) || count < 0) {
      throw new Error(`plan.${difficulty} 必须是 ≥ 0 的整数，收到: ${count}`);
    }
    for (let i = 0; i < count; i++) {
      slots.push({ difficulty, slot: slot++ });
    }
  }
  if (slots.length === 0) {
    throw new Error("计划为空：至少为一个难度配置篇数");
  }
  return slots;
}

/**
 * 每日文章生成：按计划展开槽位建批次/槽位行；已收口批次直接返回既有结果
 * （不重跑），未收口/无批次则补齐槽位行并只补跑未完成槽位（同日重跑 = 补跑），
 * 成功后写 markdown 并入库，失败/拒绝只记槽位终态，结束时收口批次。
 *
 * - 单槽成败互不影响：generateArticle 本身不抛错（返回三态结果），runPool
 *   再兜底收集单槽异常（rejected → error 结果），保证个别槽位异常时其余
 *   槽位照常跑完；
 * - 落库编排：打开唯一 Database（cfg.dbPath），schema/批次/槽位幂等建好，
 *   最近 5 天成功文章作为去重上下文传入（标题避免雷同、URL 不重复抓取），
 *   usedUrls 每 run 一个 Set 拦截并行竞态；结束时 finalizeBatch + db.close()
 *   （异常路径 finally 兜底关闭）；
 * - 持久化职责：仅本编排层（daily.ts）与 CLIs 允许引用 src/db.ts，图节点
 *   与 generateArticle 保持"纯编排"不碰业务库。
 */
export async function generateDailyArticles(
  args: GenerateDailyArticlesArgs,
): Promise<DayResult> {
  const plan = args.plan ?? DEFAULT_DAILY_PLAN;
  const cfg = args.config ?? loadConfig();
  const limit = args.concurrency ?? cfg.slotConcurrency;
  const slots = expandPlan(plan);
  const runDate = args.runDate;

  // 持久化：确保 schema、批次、槽位行（重复运行只插缺的，成功槽位不动）
  const db = new Database(cfg.dbPath);
  try {
    ensureSchema(db);
    // ① 上批次已收口（终态）→ 不重跑、不调 LLM，直接返回既有结果
    const existing = getBatch(db, runDate);
    if (existing && existing.status !== "running") {
      const failed = listSlots(db, runDate).filter((s) => s.status !== "success").map((s) => s.slotIndex);
      log(
        `${runDate} 已执行结束(status=${existing.status}, ${existing.completedSlots}/${existing.totalSlots} 成功` +
        `${failed.length ? `, 未成功槽位: [${failed.join(", ")}]` : ""})。直接返回既有结果。`,
      );
      return dayResultFromDb(db, runDate, existing);
    }

    // 去重上下文（最近 5 天成功文章；仅图输入，不写 state 之外的东西）
    const recent = listRecentArticles(db, runDate, 5, 60);
    const recentTitles = recent.map((r) => r.titleEn);
    const recentUsedUrls = recent.flatMap((r) => (r.sourceUrl ? [r.sourceUrl] : []));
    const usedUrls = new Set<string>(); // 进程内共享：并跑槽位间去重

    // ② 存在但未执行完（running，中断/收口前崩溃）→ 修复：只补跑该批次已有的 pending
    // 槽位（已终态槽位不重复生成），不掺入今日计划、不补插新槽位

    if (existing) {
      const pendingRows = listSlots(db, runDate).filter((r) => r.status === "pending");
      return await runDay(db, cfg, existing, pendingRows, {
        runDate, recentTitles, recentUsedUrls, usedUrls, limit, llm: args.llm,
      });
    }

    // ③ 不存在 → 全新批次：createBatchAndSlots 单事务原子创建批次 + 计划全部槽位
    const planned = slots.map((s) => ({
      slotIndex: s.slot,
      difficulty: s.difficulty,
      threadId: slotThreadId(runDate, s.slot, 1),
    }));
    const batch = createBatchAndSlots(db, runDate, slots.length, planned);
    return await runDay(db, cfg, batch, listSlots(db, runDate), {
      runDate, recentTitles, recentUsedUrls, usedUrls, limit, llm: args.llm,
    });
  } finally {
    db.close();
  }
}

/**
 * 执行槽位集并收口（② 修复与 ③ 新建共用的纯执行层）：每个槽位生成→落库→
 * 打明细日志；runPool 保证单槽异常不拖垮整批（rejected 补成 error 落库终态）；
 * 跑完 finalizeBatch，结果统一由 dayResultFromDb 从库重建（含中断前已完成的槽位）。
 * 入参 rows 决定区别：新建=本批全部槽位，修复=DB 现有 pending 槽位。
 */
async function runDay(
  db: Database,
  cfg: AppConfig,
  batch: BatchRow,
  rows: SlotRow[],
  ctx: {
    runDate: string;
    recentTitles: string[];
    recentUsedUrls: string[];
    usedUrls: Set<string>;
    limit: number;
    llm?: LLM;
  },
): Promise<DayResult> {
  const poolResults = await runPool(
    rows.map((row) => async () => {
      log(slotAttemptLog("daily", row, {
        attempt: row.attempts, threadId: row.threadId, outcome: "running", started: true,
      }));
      const result = await generateArticle({
        runDate: ctx.runDate,
        difficulty: row.difficulty,
        threadId: row.threadId,
        recentTitles: ctx.recentTitles,
        recentUsedUrls: ctx.recentUsedUrls,
        usedUrls: ctx.usedUrls,
        config: cfg,
        llm: ctx.llm,
      });
      await persistSlot(db, cfg, batch.id, row, result);
      log(slotAttemptLog("daily", row, {
        attempt: row.attempts, threadId: row.threadId, outcome: result.outcome,
        reason: result.outcome === "rejected"
          ? result.reason
          : result.outcome === "error"
            ? result.message
            : undefined,
        started: false,
      }));
    }),
    ctx.limit,
  );

  // runPool 保证单槽异常不拖垮整批：rejected 槽位补成 error 结果并落终态
  for (const [i, r] of poolResults.entries()) {
    if (r.status === "rejected") {
      const row = rows[i]!;
      const result: ArticleResult = {
        outcome: "error",
        message: r.reason instanceof Error ? r.reason.message : String(r.reason),
      };
      await persistSlot(db, cfg, batch.id, row, result);
      log(slotAttemptLog("daily", row, {
        attempt: row.attempts, threadId: row.threadId, outcome: "error",
        reason: result.message, started: false,
      }));
    }
  }

  finalizeBatch(db, batch.id);
  return dayResultFromDb(db, ctx.runDate, getBatch(db, ctx.runDate)!);
}

/**
 * 从库中重建全天结果（已收口 / 补跑后的统一返回口径）：逐槽按 DB 终态生成，
 * 成功槽位从 articles + paragraphs 重建（factSheet 未持久化，重建时省略），
 * 终态的原因/消息未持久化，以占位文本标明（明细以运行日志为准）。
 */
function dayResultFromDb(db: Database, runDate: string, batch: BatchRow): DayResult {
  const results: DaySlotResult[] = listSlots(db, runDate).map((s) => {
    const base = { slot: s.slotIndex, difficulty: s.difficulty };
    if (s.status === "success" && s.articleId !== null) {
      return { ...base, result: { outcome: "success", genAttempts: s.attempts, article: articleFromDb(db, s.articleId) } };
    }
    if (s.status === "rejected") {
      return { ...base, result: { outcome: "rejected", genAttempts: s.attempts, reason: "此前运行已判定拒绝（原因未持久化，详见运行日志）" } };
    }
    if (s.status === "error") {
      return { ...base, result: { outcome: "error", genAttempts: s.attempts, message: "此前运行已判定失败（错误信息未持久化，详见运行日志）" } };
    }
    // pending 兜底：正常流程不会出现（收口前 = running 批次，未收口槽位已在前方补跑）
    return { ...base, result: { outcome: "error", genAttempts: s.attempts, message: `槽位未完成(status=${s.status})` } };
  });
  const summary = { success: 0, rejected: 0, error: 0 };
  for (const { result } of results) summary[result.outcome]++;
  return { runDate, total: batch.totalSlots, results, summary };
}

/** 成功槽位的文章从库重建（factSheet 未持久化故省略；段落按 index 序）。 */
function articleFromDb(db: Database, articleId: number): GeneratedArticle {
  const a = db
    .query(
      `SELECT run_date, difficulty, category, path, source_url, title_en, title_zh
       FROM articles WHERE id = ?`,
    )
    .get(articleId) as Record<string, unknown>;
  const paragraphs = db
    .query("SELECT text_en, text_zh FROM article_paragraphs WHERE article_id = ? ORDER BY paragraph_index")
    .all(articleId) as { text_en: string; text_zh: string }[];
  return GeneratedArticle.parse({
    runDate: a.run_date,
    difficulty: a.difficulty,
    category: a.category,
    path: a.path,
    ...(a.source_url ? { sourceUrl: a.source_url as string } : {}),
    titleEn: a.title_en,
    titleZh: a.title_zh,
    paragraphs: paragraphs.map((p) => ({ en: p.text_en, zh: p.text_zh })),
  });
}

/**
 * 槽位结果落库（模块内私有）：success 写 markdown 到 cfg.outputDir 并入 articles，
 * 失败/拒绝只写槽位终态。日志由调用方按 §4.3 打，本函数不再重复 log。
 */
async function persistSlot(
  db: Database,
  cfg: AppConfig,
  batchId: number,
  row: SlotRow,
  result: ArticleResult,
): Promise<void> {
  if (result.outcome === "success") {
    const article = result.article;
    await mkdir(cfg.outputDir, { recursive: true });
    const file = join(cfg.outputDir, `${article.runDate}-${article.category}-${Date.now()}.md`);
    await Bun.write(file, renderMarkdown(article));
    const articleId = insertArticleWithParagraphs(db, batchId, article, row.threadId, file);
    writeSlotResult(db, { slotId: row.id, threadId: row.threadId, status: "success", articleId, attempts: result.genAttempts });
    return;
  }
  const status: SlotStatus = result.outcome === "rejected" ? "rejected" : "error";
  writeSlotResult(db, { slotId: row.id, threadId: row.threadId, status, attempts: result.genAttempts });
}

export interface RetryFailedArgs {
  runDate: string;
  /** 并发槽位数上限；缺省取 cfg.slotConcurrency。 */
  concurrency?: number;
  config?: AppConfig;
  llm?: LLM;
}

export interface RetryResult {
  runDate: string;
  /** 本轮续跑（同 thread_id 从 LangGraph 快照恢复）的槽位数。 */
  resumed: number;
  /** 本轮同步图终态到 DB（崩溃间隙，不重跑）的槽位数。 */
  synced: number;
  /** 本轮处理后仍未 success 的槽位数（含业务终态不处理的 error/rejected）。 */
  stillFailed: number;
  /** 空跑提示：本轮无任何可处理槽位时给出具体说明（无执行记录 / 流程已正常结束等），有实际处理时为 null。 */
  note: string | null;
}

export type SlotDecision = "resume" | "sync" | "skip";

/**
 * 重试分派（纯函数）——retry CLI 只解决程序崩溃导致的中断（LangGraph 断点续跑特性），
 * 不做业务刷重试：
 * - pending（未完成/中途退出）+ checkpointer 无终态 → resume：同 thread_id 续跑，
 *   由 LangGraph 快照推进；
 * - pending + checkpointer 已有终态（崩溃间隙：图跑完但没落库）→ sync：把终态
 *   同步回 DB（success 写 md+入库），不重跑、不换新 id；
 * - error/rejected（业务终态，图内校验重试已在 3 轮内封顶）→ skip：不处理。
 */
export function classifySlot(args: {
  status: SlotStatus;
  checkpointOutcome?: string;
  runDate: string;
  slot: number;
}): SlotDecision {
  if (args.status !== "pending") return "skip";
  return args.checkpointOutcome ? "sync" : "resume";
}

/** 从 checkpointer 判断该线程是否已到终态（有 outcome 字段）。 */
async function checkpointOutcomeOf(
  cp: BunSqliteCheckpointer,
  threadId: string,
): Promise<string | undefined> {
  const tuple = await cp.getTuple({ configurable: { thread_id: threadId } });
  if (!tuple) return undefined;
  // langgraph checkpoint 字段是 channel_values（旧版兼容别名 values），与 replay.ts.loadState 同口径
  const checkpoint = tuple.checkpoint as unknown as {
    channel_values?: Record<string, unknown>;
    values?: Record<string, unknown>;
  };
  const channelValues = checkpoint.channel_values ?? checkpoint.values ?? {};
  return channelValues.outcome as string | undefined;
}

/**
 * 单轮重试（纯中断恢复）：只扫 run_date 的 pending 槽位。
 * 一轮 = 一次调用；「全天」由外部多次调用实现（每轮自然更新 status，失败槽位下轮接着来）。
 *
 * - 分派（classifySlot，基于 checkpointer 终态）：
 *   pending + 无终态 → resume（同 thread_id 续跑，LangGraph 快照推进）；
 *   pending + 已有终态（崩溃间隙）→ sync（toResult 同步回 DB，成功写 md+入库，不重跑）；
 *   error/rejected（业务终态，图内校验重试已封顶）→ 不处理。
 * - 单槽成败互不影响：generateArticle 不抛错，runPool 兜底 rejected → error 落库；
 * - 若批次不存在 → 全零结果（收口无意义）；无 pending 槽位 → 直接收口批次。
 */
export async function retryFailedSlots(args: RetryFailedArgs): Promise<RetryResult> {
  const cfg = args.config ?? loadConfig();
  const limit = args.concurrency ?? cfg.slotConcurrency;
  const runDate = args.runDate;

  const db = new Database(cfg.dbPath);
  try {
    ensureSchema(db);
    const batch = getBatch(db, runDate);
    if (!batch) {
      return { runDate, resumed: 0, synced: 0, stillFailed: 0, note: `${runDate} 无执行记录，无需重试。` };
    }
    const slots = listSlots(db, runDate).filter((s) => s.status === "pending");
    if (slots.length === 0) {
      // 空跑：流程已正常结束（或收口前崩溃已由槽位终态兜底），无中断需要恢复
      finalizeBatch(db, batch.id);
      const closed = getBatch(db, runDate)!;
      const failed = listSlots(db, runDate).filter((s) => s.status !== "success").length;
      const note = closed.status === "completed"
        ? `${runDate} 流程已正常结束（${closed.totalSlots}/${closed.totalSlots} 槽全部成功），无中断槽位可恢复。`
        : `${runDate} 流程已正常结束（status=${closed.status}，${closed.completedSlots}/${closed.totalSlots} 成功），` +
        `无中断槽位可恢复；${failed} 个未成功槽位为业务终态（rejected/error），如需重跑请人工处置。`;
      return { runDate, resumed: 0, synced: 0, stillFailed: failed, note };
    }
    const recent = listRecentArticles(db, runDate, 5, 60);
    const recentTitles = recent.map((r) => r.titleEn);
    const recentUsedUrls = recent.flatMap((r) => (r.sourceUrl ? [r.sourceUrl] : []));
    const usedUrls = new Set<string>(); // 进程内共享：并跑槽位间去重
    const cp = new BunSqliteCheckpointer(cfg.checkpointPath);

    // 分派：pending 查 checkpoint → resume / sync
    const toResume: SlotRow[] = [];
    const toSync: SlotRow[] = [];
    for (const slot of slots) {
      const outcome = await checkpointOutcomeOf(cp, slot.threadId);
      const decision = classifySlot({
        status: slot.status,
        checkpointOutcome: outcome,
        runDate,
        slot: slot.slotIndex,
      });
      (decision === "resume" ? toResume : toSync).push(slot);
    }

    const settled = await runPool(
      toResume.map((row) => async () => {
        log(slotAttemptLog("retry", row, {
          attempt: row.attempts, threadId: row.threadId, outcome: "running", started: true,
        }));
        const result = await generateArticle({
          runDate,
          difficulty: row.difficulty,
          threadId: row.threadId,
          recentTitles,
          recentUsedUrls,
          usedUrls,
          config: cfg,
          llm: args.llm,
        });
        await persistSlot(db, cfg, batch.id, row, result);
        log(slotAttemptLog("retry", row, {
          attempt: row.attempts, threadId: row.threadId, outcome: result.outcome,
          reason: result.outcome === "rejected"
            ? result.reason
            : result.outcome === "error"
              ? result.message
              : undefined,
          started: false,
        }));
        return result;
      }),
      limit,
    );

    // runPool 兜底（generateArticle 本身不抛，此分支只防万一）：槽位按 error 落库
    for (const [i, r] of settled.entries()) {
      if (r.status === "rejected") {
        const row = toResume[i]!;
        const result: ArticleResult = {
          outcome: "error",
          message: r.reason instanceof Error ? r.reason.message : String(r.reason),
        };
        await persistSlot(db, cfg, batch.id, row, result);
        log(slotAttemptLog("retry", row, {
          attempt: row.attempts, threadId: row.threadId, outcome: "error",
          reason: result.message, started: false,
        }));
      }
    }

    // 崩溃间隙：图已跑完但槽位未落库 → 从 checkpoint 同步终态（不重跑）
    for (const row of toSync) {
      const tuple = await cp.getTuple({ configurable: { thread_id: row.threadId } });
      const checkpoint = tuple!.checkpoint as unknown as {
        channel_values?: Record<string, unknown>;
        values?: Record<string, unknown>;
      };
      const state = checkpoint.channel_values ?? checkpoint.values ?? {};
      const result = toResult(state as typeof ArticleGenState.State, byCategory);
      await persistSlot(db, cfg, batch.id, row, result);
      log(slotAttemptLog("retry", row, {
        attempt: row.attempts, threadId: row.threadId, outcome: result.outcome,
        reason: result.outcome === "rejected"
          ? result.reason
          : result.outcome === "error"
            ? result.message
            : undefined,
        started: false,
      }));
    }

    finalizeBatch(db, batch.id);
    const stillFailed = listSlots(db, runDate).filter((s) => s.status !== "success").length;
    return { runDate, resumed: toResume.length, synced: toSync.length, stillFailed, note: null };
  } finally {
    db.close();
  }
}
