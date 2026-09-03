import { z } from "zod";

export const Difficulty = z.enum(["LOW", "MEDIUM", "HIGH"]);
export type Difficulty = z.infer<typeof Difficulty>;

const LOW_CATEGORIES = ["daily_conversation", "scene_description", "simple_story"] as const;
const MEDIUM_CATEGORIES = ["news", "expository", "argumentative", "personal_essay"] as const;
const HIGH_CATEGORIES = ["academic_abstract", "debate_speech", "legal_document", "art_criticism"] as const;

export const CATEGORIES_BY_DIFFICULTY: Record<Difficulty, readonly Category[]> = {
  LOW: LOW_CATEGORIES,
  MEDIUM: MEDIUM_CATEGORIES,
  HIGH: HIGH_CATEGORIES,
};

export const Category = z.enum([...LOW_CATEGORIES, ...MEDIUM_CATEGORIES, ...HIGH_CATEGORIES]);
export type Category = z.infer<typeof Category>;

export const FactSheet = z.object({
  who: z.string().default(""),
  what: z.string().default(""),
  when: z.string().default(""),
  where: z.string().default(""),
  why: z.string().default(""),
  how: z.string().default(""),
  keyNumbers: z.array(z.string()).default([]),
  keyNames: z.array(z.string()).default([]),
});
export type FactSheet = z.infer<typeof FactSheet>;

// Paragraph-level pairing (English, Chinese) instead of two whole-article
// strings — keeps the storage layer (see db/schema.ts) and any future
// paragraph-aligned reading feature naturally in sync, and makes it possible
// to validate "this one paragraph doesn't line up" at a finer grain.
export const ArticleParagraph = z.object({
  en: z.string().min(1),
  zh: z.string().min(1),
});
export type ArticleParagraph = z.infer<typeof ArticleParagraph>;

export const BilingualArticle = z.object({
  titleEn: z.string().min(1),
  titleZh: z.string().min(1),
  paragraphs: z.array(ArticleParagraph).min(1),
});
export type BilingualArticle = z.infer<typeof BilingualArticle>;

/**
 * 生成节点的模型输出（判别联合）。
 * 模型判定主题违规/缺依据时必须输出 cannot_write 变体——结构化拒答信号。
 * 旧方案靠模型输出散文话术整句相等反猜（jsonMode 下散文必然解析失败），
 * 判定不可靠；新方案下拒答是合法 JSON，程序可精确分类。
 */
export const GenerateResult = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("article"),
    titleEn: z.string().min(1),
    titleZh: z.string().min(1),
    paragraphs: z.array(ArticleParagraph).min(1),
  }),
  z.object({ type: z.literal("cannot_write") }),
]);
export type GenerateResult = z.infer<typeof GenerateResult>;


export const PipelineState = z.object({
  // --- scheduling input ---
  runDate: z.string(), // ISO date, e.g. "2026-08-21"
  batchId: z.number(),
  /** Zero-based slot order within the batch; recorded in run_log for attribution. */
  slot: z.number(),
  difficulty: Difficulty,
  category: Category,
});
export type PipelineState = z.infer<typeof PipelineState>;


export function createInitialState(input: z.input<typeof PipelineState>): PipelineState {
  return PipelineState.parse(input);
}