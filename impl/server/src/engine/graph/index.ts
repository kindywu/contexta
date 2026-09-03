import { loadConfig, type AppConfig } from "../config";
import type { Category, Difficulty } from "../schema";
import type { SiteEntry } from "../sites";
import { byCategory } from "../sites.config";
import { createLLM, type LLM } from "../llm";
import { BunSqliteCheckpointer } from "./checkpointer";
import { buildArticleGraph } from "./graph";
import { resolvePath } from "./nodes";
import {
  ArticleResult,
  GeneratedArticle,
  type ArticleGenState,
} from "./state";
import { REJECTION_MESSAGE } from "./prompts";

export interface GenerateArticleArgs {
  runDate: string; // ISO 日期，如 "2026-08-28"
  difficulty: Difficulty;
  /**
   * 断点线程 id。同一 threadId 重复调用 = 续跑：已完成的节点从 checkpointer
   * 恢复而非重跑（fetchSource 抓取和 generate 的 LLM 调用都不浪费）。
   * 缺省自动生成一个随机 id（每次调用一条新线程）。
   */
  threadId?: string;
  config?: AppConfig;
  llm?: LLM;
  recentTitles?: string[];      // 最近5天成功文章标题（生成 prompt 避免雷同；缺省 []）
  recentUsedUrls?: string[];    // 最近5天成功文章 source_url（fetchSource 去重；缺省 []）
  usedUrls?: Set<string>;       // 进程内共享去重集合（并行槽位竞态；缺省 new Set()）
}

export type { ArticleResult, GeneratedArticle };

/** 终态 state → 对外三态结果（genAttempts = 图内实际生成轮数，供槽位 attempts 写回）。 */
export function toResult(
  state: typeof ArticleGenState.State,
  sitesByCategory: Partial<Record<Category, SiteEntry[]>>,
): ArticleResult {
  const genAttempts = state.genAttempts ?? 1;
  if (state.outcome === "success") {
    const path = resolvePath(state.category, sitesByCategory);
    const article = GeneratedArticle.parse({
      runDate: state.runDate,
      difficulty: state.difficulty,
      category: state.category,
      path,
      ...(state.sourceUrl ? { sourceUrl: state.sourceUrl } : {}),
      ...(state.factSheet ? { factSheet: state.factSheet } : {}),
      titleEn: state.draft!.titleEn,
      titleZh: state.draft!.titleZh,
      paragraphs: state.draft!.paragraphs,
    });
    return { outcome: "success", genAttempts, article };
  }
  if (state.outcome === "rejected") {
    return { outcome: "rejected", genAttempts, reason: state.reason || REJECTION_MESSAGE };
  }
  return { outcome: "error", genAttempts, message: state.reason || "未知错误" };
}

/**
 * 文章生成流程（无状态函数）：接受日期 + 难度，产出三态结果。
 * 内部通过 checkpointer 落盘 LangGraph 自身状态（data/langgraph.sqlite，
 * 与业务库 data/pipeline.sqlite 无关），因此:
 * - 进程崩溃/网络故障后可传同一 threadId 断点续跑；
 * - 持续失败（欠费、站点全挂）返回 outcome=error；校验违规在图内带违规反馈自动重写
 *   （默认最多 3 轮含首试，见 graph.ts 的 maxGenRounds），封顶仍违规才返回 rejected，
 *   不会抛出。
 *
 * 不需要数据库读写：本文档不涉及 articles/batches 等业务表。
 */
export async function generateArticle(
  args: GenerateArticleArgs,
): Promise<ArticleResult> {
  const cfg = args.config ?? loadConfig();
  const llm = args.llm ?? createLLM(cfg);
  const sitesByCategory = byCategory;
  const threadId = args.threadId ?? `manual-${args.runDate}-${Date.now()}`;
  const checkpointer = new BunSqliteCheckpointer(cfg.checkpointPath);

  const graph = buildArticleGraph({
    deps: { llm, sitesByCategory, rng: Math.random, usedUrls: args.usedUrls ?? new Set<string>() },
    checkpointer, // 每个 superstep 落盘，进程中断后同 threadId 可断点续跑
  });

  // 同一 threadId 已有进度 → 断点续跑：不再传输入参数（runDate/difficulty 从
  // checkpoint 恢复），LangGraph 只会跑未完成的节点。
  const existing = await checkpointer.getTuple({ configurable: { thread_id: threadId } });
  const input = existing
    ? null
    : {
        runDate: args.runDate,
        difficulty: args.difficulty,
        recentTitles: args.recentTitles ?? [],
        recentUsedUrls: args.recentUsedUrls ?? [],
      };

  try {
    const state = await graph.invoke(input as never, {
      configurable: { thread_id: threadId },
    });
    return toResult(state, sitesByCategory);
  } catch (e) {
    return { outcome: "error", message: e instanceof Error ? e.message : String(e) };
  }
}
