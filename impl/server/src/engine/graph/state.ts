import { Annotation } from "@langchain/langgraph";
import { z } from "zod";
import {
  BilingualArticle,
  Category,
  Difficulty,
  FactSheet,
} from "../schema";
import type { ArticleLink } from "../sites";

/** 校验器报告的单个违规项（ruleId 约定见 src/graph/prompts.ts 中的判官 prompt）。 */
export const Violation = z.object({
  ruleId: z.string(),
  message: z.string(),
});
export type Violation = z.infer<typeof Violation>;

/** 安全校验判官的输出：通过与否 + 违规清单。 */
export const SafetyVerdict = z.object({
  passed: z.boolean(),
  violations: z.array(Violation).default([]),
});
export type SafetyVerdict = z.infer<typeof SafetyVerdict>;

/** 三态：成功 / 合规拒绝 / 技术失败（网络、欠费、站点挂）。 */
export const ArticleOutcome = z.enum(["success", "rejected", "error"]);
export type ArticleOutcome = z.infer<typeof ArticleOutcome>;

/**
 * 流程输出，字段对齐 articles 表（docs/database-schema.md）。
 * 表里的 paragraph_count / embedding / markdown_path 属存储层派生，不在生成流程内。
 */
export const GeneratedArticle = BilingualArticle.extend({
  runDate: z.string(),
  difficulty: Difficulty,
  category: Category,
  /** 对应 articles.path：A=有权威来源支撑，B=模型知识生成 */
  path: z.enum(["A", "B"]),
  /** 对应 articles.source_url；pathA 必有 */
  sourceUrl: z.string().optional(),
  /** pathA 抽取的事实卡（可审计） */
  factSheet: FactSheet.optional(),
});
export type GeneratedArticle = z.infer<typeof GeneratedArticle>;

export const ArticleResult = z.discriminatedUnion("outcome", [
  z.object({ outcome: z.literal("success"), genAttempts: z.number().optional(), article: GeneratedArticle }),
  z.object({ outcome: z.literal("rejected"), genAttempts: z.number().optional(), reason: z.string() }),
  z.object({ outcome: z.literal("error"), genAttempts: z.number().optional(), message: z.string() }),
]);
export type ArticleResult = z.infer<typeof ArticleResult>;

/**
 * LangGraph 运行时状态（checkpointer 落盘，纯内存语义，无业务库读写）。
 * 输入部分（runDate/difficulty）由调用方给定，其余字段由各节点按序写入。
 */
export const ArticleGenState = Annotation.Root({
  // --- 输入（不可变） ---
  runDate: Annotation<string>, // ISO 日期，如 "2026-08-28"
  difficulty: Annotation<Difficulty>,
  // --- 去重上下文（调用方从业务库查询后传入；旧 checkpoint 恢复时 undefined，消费方 ?? []） ---
  recentTitles: Annotation<string[]>,
  recentUsedUrls: Annotation<string[]>,
  // --- pickCategory 产出 ---
  category: Annotation<Category>,
  // --- pathA 专属 ---
  /** 候选列表来自的站点名（chooseArticle 用它解析 adapter，避免把站点函数序列化进 checkpoint） */
  sourceSiteName: Annotation<string>,
  /** fetchLinks 抓到的候选链列表；选一篇移出一篇——extractFacts 空卡换源时复用，不再抓列表 */
  sourceLinks: Annotation<ArticleLink[]>,
  /** 源抽取轮数（chooseArticle 抓正文成功后 +1，首试 = 1）；extractFacts 空卡换源封顶见 maxSourcePicks */
  sourceAttempts: Annotation<number>,
  sourceTitle: Annotation<string>,
  sourceUrl: Annotation<string>,
  sourceMarkdown: Annotation<string>,
  factSheet: Annotation<FactSheet>,
  // --- 生成与校验 ---
  draft: Annotation<BilingualArticle>,
  /** 生成轮数（每次 generate +1，首试 = 1）。校验违规时带违规反馈回边重写，封顶见 graph.ts 的 maxGenRounds。 */
  genAttempts: Annotation<number>,
  /** 最近一次校验的违规（成功时清空）。违规 → 图内带反馈自动重试（最多 maxGenRounds 轮含首试），封顶仍违规 → rejected。 */
  lastViolations: Annotation<Violation[]>,
  // --- 终态 ---
  outcome: Annotation<ArticleOutcome>,
  reason: Annotation<string>,
  /** generate 侧业务拒答标记（模型输出 cannot_write / 拒答话术）：本来源/主题不可写，
   *  图据此路由换源（generateA → chooseArticle 回边；B 无源 → 终态）。 */
  genFailure: Annotation<"refused">,
});
