import type { Category, Difficulty } from "../schema";
import type { Violation } from "./state";
import { memberList } from "../const/coreLeaders";

/**
 * 所有 AI 提示词的唯一来源。
 * 平台规则硬编码自 docs/prompt.md（第五节精简英文版 + 中文红线话术），
 * 改动时同步该文档；拒绝话术两者保持一致。
 */

/** prompt.md 规定的一票否决红线（英文精简版，见 docs/prompt.md 第五节）。 */
export const REDLINE_RULES_EN = `Generate English articles for English-learning purposes, strictly following the rules below.
Reject the request directly if it is risky, controversial, or unverifiable — do not attempt to rephrase around the restriction.

STRICTLY FORBIDDEN:
- Fabricated political content; invented statements, deeds, or motives attributed to national leaders.
- Fabricated stories or quotes falsely attributed to real celebrities or historical figures.
- Sensitive geopolitical topics (e.g. major historical political events, cross-strait or territorial disputes) — do not take a stance.
- Disputed territorial/sovereignty claims stated as one-sided fact.
- Basic geography/climate errors (e.g. snow in tropical cities, reversed hemispheric seasons).
- Extremism, hate speech, regional or gender discrimination, cults.
- Sexual, violent, terrorist, drug-related, gambling, self-harm, or crime-instructional content.
- Fabricated medical advice or pseudoscience.
- Distorted history, glorification of aggression, defamation of historical figures.
- Unverified rumors, conspiracy theories, fabricated statistics.
- Investment predictions, stock tips, or guaranteed-return financial claims.
- Verbatim reproduction of large portions of copyrighted text (lyrics, poems, novel excerpts).
- Defamatory claims about living public figures.

FACTUAL REQUIREMENTS:
- News content must be based on verifiable, reputable official sources.
- Science content (Newtonian mechanics, relativity, quantum mechanics, etc.) must reflect mainstream scientific consensus; unsettled hypotheses must be labeled as such.
- Geography/travel content must reflect commonly accepted, verifiable facts.
- State facts objectively — do not insert subjective value judgments, especially on historical, social, or current-affairs topics.
- Avoid obscure academic jargon; keep language accessible to general learners.

ENCOURAGED (for learning value and variety):
- Real, verifiable quotes from classic literature, proverbs, or historical figures — keep quotes short, cite the source, never invent an attribution.
- Real, verifiable local customs, festivals, and everyday cultural details.
- Common idioms/slang with brief explanations.
- Everyday dialogue scenarios (shopping, travel, work, socializing).
- A mix of narrative, expository, argumentative, letter, diary, and dialogue formats to avoid repetitive templates.`;

/** prompt.md 规定的拒绝话术（四、5）。 */
export const REJECTION_MESSAGE = "该主题存在合规风险或缺少可靠依据，无法生成文章。";

/** 难度 → CEFR 学习等级（prompt.md 四、3 允许按 A2/B1/B2/C1 分级）。 */
export const CEFR_BY_DIFFICULTY: Record<Difficulty, string> = {
  LOW: "A2",
  MEDIUM: "B1",
  HIGH: "B2",
};

/** 每个类别的写作指引（文体/内容侧重，prompt.md 三、5 鼓励文体多样性）。 */
export const CATEGORY_GUIDANCE: Record<Category, string> = {
  daily_conversation:
    "对话体：围绕一个日常情景（购物、旅行、职场、社交等），以人物对话为主，句子简短实用",
  scene_description:
    "场景描写：静态或动态场景的细节描绘，多用感官词汇，画面感强",
  simple_story:
    "简短故事：情节简单完整，人物明确，明显是虚构创作（注：文中需标明为虚构故事）",
  news:
    "新闻报道体：只陈述事实，逐字基于权威来源信息，不得添加来源之外的细节、推测或评价",
  expository:
    "说明文：向学习者解释一个知识话题，客观中立，事实基于权威来源",
  argumentative:
    "议论文：提出观点与论证，但表达克制冷静，正反两面按比例覆盖，不煽动情绪",
  personal_essay:
    "个人随笔：第一人称视角，主题贴近日常生活学习，观点温和不偏激",
  academic_abstract:
    "学术摘要体：引述教科书级通行学术共识，未定论假说须标注「学界尚无共识」",
  debate_speech:
    "辩论演讲稿：开头有立场，正文正反论证，结尾小结；语言有力但不过激",
  legal_document:
    "法律文书体：一般性法律常识科普，必须注明「不构成法律建议」，不做个案指导",
  art_criticism:
    "艺术评论：评述公认的经典艺术作品或公共艺术现象，避免对在世人物的贬损性评价",
};

/** 目标段落数范围（写进生成 prompt，保持学习文章可读性）。 */
export const TARGET_PARAGRAPHS = "6-10";

/** pathA 生成多带的一段素材：事实卡 + 权威正文。 */
function buildSourceMaterial(
  sourceTitle: string,
  sourceUrl: string,
  sourceMarkdown: string,
  factSheetJson: string,
): string {
  return `AUTHORITATIVE SOURCE (fact reference only):
Title: ${sourceTitle}
URL: ${sourceUrl}
FACT SHEET extracted from the source (who/what/when/where/why/how/keyNumbers/keyNames):
${factSheetJson}
SOURCE EXCERPT:
${sourceMarkdown}`;
}

/** 生成节点的 system prompt。 */
export function buildGenerateSystemPrompt(params: {
  difficulty: Difficulty;
  category: Category;
  path: "A" | "B";
}): string {
  const { difficulty, category, path } = params;
  const cefr = CEFR_BY_DIFFICULTY[difficulty];
  const guidance = CATEGORY_GUIDANCE[category];
  const pathRules =
    path === "A"
      ? `Path A rules (source-backed):
- Write ONLY facts present in the provided authoritative source. Never add details, numbers, or names that are not in the source or its fact sheet.
- Reference the source naturally (e.g. "as reported by ...").
- No speculation, no comparison with unrelated facts, no value judgments.`
      : `Path B rules (knowledge-based):
- Write from reliable general knowledge only. For any quote/attribution, use only ones you are certain are real and verifiable; when unsure, invent the idea instead of the attribution.
- If the article is fictional, say so clearly in the first paragraph.
- Avoid making subjective value judgments on controversial topics.
ABSOLUTELY FORBIDDEN:
- NEVER mention, reference, quote, describe, or construct any content around the following named persons. The article must not contain ANY of these Chinese names (in titles, English text, or Chinese text), and must not be about them, their quotes, their works, or their deeds:
${memberList.join("、")}`;

  return `You are a bilingual English-learning article writer. ${REDLINE_RULES_EN}

TASK SPEC:
- Difficulty level: ${difficulty} (CEFR ${cefr}), vocabulary and sentence complexity must match.
- Category: ${category}. ${guidance}
- Target: ${TARGET_PARAGRAPHS} paragraphs, each 50-120 English words, English and Chinese paragraph-aligned.
- Output: an English title and a Chinese title.
- The article is for language learning; keep it informative and engaging.
- If the topic would violate any forbidden rule or lacks credible grounding, refuse by outputting exactly:
  {"type":"cannot_write"}
  Do not produce vague or borderline content instead, and never reply with a prose refusal sentence.

${pathRules}

OUTPUT FORMAT: strictly the JSON schema given — for the article:
{"type":"article", titleEn, titleZh, paragraphs: array of {en, zh}};
for refusal: {"type":"cannot_write"}.`;
}

/**
 * 生成节点的 user 内容：素材 + 上次校验的违规反馈（若有）+ 本槽选题（若有）
 * + 近期文章标题（去重约束）。
 *
 * topic 由 pickTopic 节点规划（pathB；pathA 的选题由来源决定，不传）。带着选题生成时，
 * 近期标题块的措辞必须从"你自己挑一个不一样的"改成"题材已定，别借用这些的写法"——
 * 否则两条指令互相打架，模型会退回自由选题（2026-09-17 三篇伞文事故）。
 */
export function buildGenerateUserContent(params: {
  category: Category;
  path: "A" | "B";
  sourceTitle: string;
  sourceUrl: string;
  sourceMarkdown: string;
  factSheetJson: string;
  lastViolations: Violation[];
  recentTitles: string[];
  /** 本槽选题（pickTopic 产出）；空 = 模型自由选题（pathA / 规划失败时的兜底） */
  topic?: string;
}): string {
  const { category, path, lastViolations, recentTitles } = params;
  const material =
    path === "A"
      ? buildSourceMaterial(
          params.sourceTitle,
          params.sourceUrl,
          params.sourceMarkdown,
          params.factSheetJson,
        )
      : "";
  const feedback =
    lastViolations.length > 0
      ? `\n\nREVISION REQUIRED — your previous draft failed safety review. Fix ALL of the following before writing:
${lastViolations.map((v) => `  - [${v.ruleId}] ${v.message}`).join("\n")}
Remove or rewrite the offending content; do not argue with the reviewer.`
      : "";
  const topic = params.topic?.trim();
  const topicBlock = topic
    ? `\nTOPIC — write about exactly this subject; do not switch to another topic: ${topic}`
    : "";
  const dedup = recentTitles.length > 0
    ? topic
      ? `\n\nALREADY PUBLISHED RECENTLY (the TOPIC above stays fixed — keep it, but do not reuse any of these titles' subject, setting, objects, characters, or plot):
${recentTitles.map((t) => `- "${t}"`).join("\n")}`
      : `\n\nRECENTLY PUBLISHED ARTICLES (choose a topic and angle NOT similar to these; do not retell the same event, facts, example, or news story, even in a different category):
${recentTitles.map((t) => `- "${t}"`).join("\n")}`
    : "";
  return `Write a bilingual English-learning article for category "${category}".${topicBlock}${material}${feedback}${dedup}`;
}

/**
 * 选题规划（pickTopic 节点）的 system prompt：为单个槽位规划一个"没写过"的选题。
 * 关键约束：题材必须在**主题 + 角度**两个维度上都与已用过的不同——只换名词修饰语
 * （蓝伞/黄伞/拿错的伞）不算新选题；这正是 2026-09-17 三篇伞文的失败形态。
 */
export function buildTopicPlannerSystem(): string {
  return `You are the editorial planner of a bilingual (English/Chinese) English-learning article pipeline. Propose ONE topic for the article slot described in the user message, so the pipeline keeps publishing varied material.

RULES:
- Reply with exactly one topic, written in English as a single short concrete phrase (no quotes, no trailing period) naming who/what/where — e.g. "a first-time subway rider is helped by a stranger".
- The topic must differ from every ALREADY USED entry in BOTH subject and angle: vary the setting, the main object, the characters, and the type of situation. Renaming the same thing (e.g. "The Blue Umbrella" instead of "The Yellow Umbrella") is NOT a new topic, and neither is the same plot with a different object.
- Match the slot's difficulty (CEFR level) and its category format guidance.
- Prefer concrete everyday situations: clear characters, one simple event or exchange.
- Keep the topic inside the platform's safety red lines (a bad topic wastes a whole article, and the red lines are strict): no politics, geopolitics or modern political history; never build a topic around a real public or political figure (especially Chinese leaders), a living celebrity, or a named organization; no religion, sex, violence, crime, drugs, gambling, or medical/financial advice. Invent ordinary characters instead of naming real people.
Respond strictly in the given JSON schema.`;
}

/** 选题规划的 user 内容：槽位规格（难度/类别/文体）+ 已用过的标题与选题。 */
export function buildTopicPlannerUser(params: {
  runDate: string;
  difficulty: Difficulty;
  category: Category;
  recentTitles: string[];
  takenTopics: string[];
  /** 上一轮被拒的选题（附拒绝原因），让模型知道为什么重问 */
  rejectedTopic?: string;
}): string {
  const { runDate, difficulty, category, recentTitles, takenTopics, rejectedTopic } = params;
  const cefr = CEFR_BY_DIFFICULTY[difficulty];
  const used = [
    ...recentTitles.map((t) => `- title: "${t}"`),
    ...takenTopics.map((t) => `- topic already assigned today: "${t}"`),
  ].join("\n");
  const retry = rejectedTopic
    ? `\n\nYOUR PREVIOUS SUGGESTION WAS REJECTED: "${rejectedTopic}" — it repeats what is already covered above. Propose a clearly different one.`
    : "";
  return `TODAY: ${runDate}
SLOT: difficulty ${difficulty} (CEFR ${cefr}) | category ${category} | format: ${CATEGORY_GUIDANCE[category]}

ALREADY USED (do not repeat):
${used || "- (none)"}${retry}`;
}

/** 事实卡抽取（extractFacts）：只允许提取原文出现的字段。 */
export function buildFactExtractionSystem(): string {
  return `You extract facts from a news article. Rules:
- Include ONLY facts explicitly present in the provided article text. Never add general knowledge, background, or inference.
- who/what/when/where/why/how: one concise phrase each; empty string if the article does not state it.
- keyNumbers: numbers stated in the article (dates, ages, quantities, percentages). Keep the unit; when the article binds a number to an object (e.g. 「青稞20吨」「搜救热索村民2人」), include the object plus the number (e.g. "青稞20吨"), so the quantity stays attributable.
- keyNames: named people, organizations, places mentioned in the article.
- If the article is not a factual article (e.g. it is an ad, a list, or unrelated content), return all fields empty.
Reply strictly in the given JSON schema.`;
}

/** 事实卡抽取的 user 内容：权威正文。 */
export function buildFactExtractionUser(sourceTitle: string, sourceMarkdown: string): string {
  return `Article title: ${sourceTitle}\n\nArticle text:\n${sourceMarkdown}`;
}

/** 红线判官（pathA 通用版 / pathB 从严版）。
 * pathA 的 user 消息里会带来源全文 + 事实卡 + 当前日期（见 buildRedlineJudgeUser），
 * 判官据此把具体数字归因到来源，不再只凭文章文本判 unverified。 */
export function buildRedlineJudgeSystem(path: "A" | "B", runDate: string): string {
  const strictness =
    path === "B"
      ? `This article was generated from model knowledge (no source reference), so verify ONLY what needs no source verification:
- Any quote/attribution to a real person, proverb, or classic work must be identifiable and well-known; otherwise flag it ("the quote may be invented or misattributed").
- Any specific number or statistic being presented as fact must be accepted general knowledge; otherwise flag it.
- When in doubt, flag. Prefer a false positive over passing unverifiable content.`
      : `This article cites an authoritative source whose full text is provided in the user message along with the extracted fact sheet. Judge against that source:
- Specific figures, dates, names, and events that appear in the source text or fact sheet are verifiable — do NOT flag them as unverified merely because they are specific.
- Flag as unverified only claims attributable to NEITHER the provided source NOR well-established general knowledge.
- The current date is ${runDate}: dates on or before ${runDate} are not "future dates" and must not be flagged as fabricated/unverifiable on that basis.
- If the source (not a quote of the source) seems fabricated on its face, flag it.`;
  return `You are a strict safety compliance reviewer for bilingual English-learning articles.
The article MUST comply with all the rules below (source: docs/prompt.md):
${REDLINE_RULES_EN}

Checklist:
1. Red lines (STRICTLY FORBIDDEN list above) — any hit is a violation.
2. Subjective judgments on controversial topics — flag.
3. Unverified quotes/attributions/statistics — flag.
${strictness}

Respond strictly in the given JSON schema: {"passed": boolean, "violations": [{"ruleId": "...", "message": "..."}]}.
ruleId should be "redline", "subjective", or "unverified". If the article is clean, pass with an empty violations list.`;
}

/** pathA 事实一致性判官：文章事实不得超出权威来源的范围。
 * 判据是「事实卡」+「来源全文」两者：事实卡是有损摘要，判官必须可以退而核对全文
 * （例如事实卡里"450余件套"丢失了"帐篷"、漏掉"16时"；全文里有就不算添加）。
 * 当前日期由调用方传入，避免把今天发布的公告误判为"未来日期"。 */
export function buildConsistencyJudgeSystem(runDate: string): string {
  return `You are a fact-consistency reviewer. Compare a generated bilingual article against an authoritative source (title, URL, fact sheet AND full source text; the fact sheet is a lossy summary — the source text is the ground truth). Rules:
- Flag a factual detail in the article (numbers, dates, names, events, statistics) ONLY if it appears in NEITHER the fact sheet NOR the full source text.
- The fact sheet may omit or partially record a fact (a number without its object/unit/context); rely on the source text to fill gaps — do not flag what the source text supports.
- Paraphrase/translation is fine; fabrication is not. Reordering facts is fine; adding facts is not.
- If the article makes zero use of the source (unrelated content), flag it ("does not use the source").
- The current date is ${runDate}: dates on or before ${runDate} are not "future dates".
- Never flag vocabulary choices, style, or paraphrasing.

Respond strictly in the given JSON schema: {"passed": boolean, "violations": [{"ruleId": "consistency", "message": "..."}]}. If consistent with the source, pass with an empty violations list.`;
}

/** 事实一致性判官的 user 内容：来源标题/URL + 事实卡 + 来源全文 + 文章。 */
export function buildConsistencyJudgeUser(params: {
  sourceTitle: string;
  sourceUrl: string;
  factSheetJson: string;
  sourceMarkdown: string;
  articleJson: string;
}): string {
  return `SOURCE:
Title: ${params.sourceTitle}
URL: ${params.sourceUrl}
FACT SHEET (lossy summary):
${params.factSheetJson}

SOURCE TEXT (full, ground truth):
${params.sourceMarkdown}

GENERATED ARTICLE (JSON):
${params.articleJson}`;
}

/** 红线判官的 user 内容：文章 JSON；pathA 附带来源全文 + 事实卡（供归因）。 */
export function buildRedlineJudgeUser(params: {
  articleJson: string;
  sourceTitle?: string;
  sourceUrl?: string;
  sourceMarkdown?: string;
  factSheetJson?: string;
}): string {
  const { articleJson, sourceTitle, sourceUrl, sourceMarkdown, factSheetJson } = params;
  const source = sourceMarkdown
    ? `AUTHORITATIVE SOURCE (full text, fact reference):
Title: ${sourceTitle ?? ""}
URL: ${sourceUrl ?? ""}
FACT SHEET:
${factSheetJson ?? "{}"}
SOURCE TEXT:
${sourceMarkdown}`
    : "";
  return `${source}${source ? "\n\n" : ""}Review this bilingual article for compliance:\n${articleJson}`;
}
