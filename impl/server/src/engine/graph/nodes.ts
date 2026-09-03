/** 图的节点实现。节点都是纯输入(state) → 部分 state 更新的函数；依赖经闭包注入。 */

import TurndownService from "turndown";
import {
  BilingualArticle,
  CATEGORIES_BY_DIFFICULTY,
  Category,
  FactSheet,
  GenerateResult,
} from "../schema";
import type { ArticleLink, SiteEntry } from "../sites";
import { memberList } from "../const/coreLeaders";
import { dedupe, stripQuery } from "../sites/common";
import { callLLMStructured, type LLM } from "../llm";
import {
  buildConsistencyJudgeSystem,
  buildConsistencyJudgeUser,
  buildFactExtractionSystem,
  buildFactExtractionUser,
  buildGenerateSystemPrompt,
  buildGenerateUserContent,
  buildRedlineJudgeSystem,
  buildRedlineJudgeUser,
  REJECTION_MESSAGE,
} from "./prompts";
import { SafetyVerdict, type ArticleGenState } from "./state";
import { log } from "./log";

/** 权威正文喂给 LLM 前的截断上限（字符），防止上下文超长。 */
const SOURCE_MAX_CHARS = 12_000;

/** 图节点依赖：LLM、类别→站点条目映射、随机数、去重集合。 */
export interface NodeDeps {
  llm: LLM;
  /** 类别 → 该类别配置的站点条目（sites.config.ts 派生；无配置类别无该键） */
  sitesByCategory: Partial<Record<Category, SiteEntry[]>>;
  rng: () => number;
  /** 进程内共享的 source_url 去重集合（多个并行槽位共享，防 fetchSource 抓取重复；Task 5 消费；generateArticle 总是传入，其余入口可缺省 undefined） */
  usedUrls?: Set<string>;
}

type State = typeof ArticleGenState.State;
type Update = Partial<State>;

const td = new TurndownService({ headingStyle: "atx" });

function rngPick<T>(items: readonly T[], rng: () => number): T {
  return items[Math.floor(rng() * items.length)]!;
}

/**
 * 节点1：按难度均匀随机选类别。纯本地，无 LLM。
 * rng() 缺省 Math.random；测试可注入固定序列。
 */
export async function pickCategoryNode(state: State, deps: NodeDeps): Promise<Update> {
  const cats = CATEGORIES_BY_DIFFICULTY[state.difficulty];
  const category = rngPick(cats, deps.rng);
  log(`pickCategory: difficulty=${state.difficulty} -> ${category} (candidates: ${cats.join(",")})`);
  return { category };
}

/**
 * 候选链的新鲜度过滤（纯函数，便于单测）：
 * 去重（dedupe）后按 stripQuery 归一化过滤——避开近 5 天已用 URL（recentUsedUrls）
 * 与本轮共享 usedUrls 集合。
 */
export function computeFreshLinks(
  links: ArticleLink[],
  recentUsedUrls: string[],
  usedUrls: Set<string>,
): ArticleLink[] {
  const used = new Set([...(recentUsedUrls ?? []).map(stripQuery), ...usedUrls]);
  return dedupe(links).filter((l) => !used.has(stripQuery(l.url)));
}

/**
 * 节点2a（pathA）：随机选一个权威站点 → 只抓列表（不选篇）。候选列表写入
 * `sourceLinks`，供 chooseArticle 随机选篇；extractFacts 空卡换源时复用列表，不重抓。
 * 已运行过（sourceLinks/sourceUrl 非空）说明从 checkpointer 恢复，跳过抓取。
 * 全部站点列表失败 → 抛错（属技术失败，由 generateArticle 层收为 outcome=error）。
 */
export async function fetchLinksNode(state: State, deps: NodeDeps): Promise<Update> {
  if (state.sourceLinks || state.sourceUrl) return {};
  // 进程内共享去重集合；手动/测试入口可能缺省（usedUrls 可选），统一绑定一次
  const usedUrls = deps.usedUrls ?? new Set<string>();
  // 只洗牌当前类别配置的站点（sites.config.ts），依次尝试；列表无可选题就换下一个站点
  const shuffled = [...(deps.sitesByCategory[state.category] ?? [])].sort(
    () => deps.rng() - 0.5,
  );
  const errors: string[] = [];
  for (const entry of shuffled) {
    try {
      const links = await entry.adapter.fetchLinks(entry.url);
      const fresh = computeFreshLinks(links, state.recentUsedUrls ?? [], usedUrls);
      if (fresh.length === 0) {
        errors.push(`${entry.name}: 列表全部与近期文章重复`);
        continue;
      }
      // 源侧名单过滤(第一段):标题即现名的候选直接出局(时政新闻标题多现名,省一次抓正文)
      const clean = fresh.filter((l) => !mentionsCoreLeader(l.title));
      if (clean.length === 0) {
        errors.push(`${entry.name}: ${fresh.length} 条候选标题全部含受限人名`);
        continue;
      }
      log(
        `fetchLinks: [${entry.name}] 列表 ${links.length} 条,可选题 ${clean.length} 条` +
          `(名单过滤 ${fresh.length - clean.length} 条)`,
      );
      return { sourceSiteName: entry.name, sourceLinks: clean };
    } catch (e) {
      log(`fetchLinks: [${entry.name}] 列表抓取失败: ${(e as Error).message}（换下一个站点）`);
      errors.push(`${entry.name}: ${(e as Error).message}`);
    }
  }
  // 全部站点列表失败：纯名单过滤 → 业务性 rejected（选题不适配）；否则技术性 error
  if (errors.length > 0 && errors.every((e) => e.includes("受限人名"))) {
    log("fetchLinks: 所有候选标题均含受限人名 -> rejected");
    return { outcome: "rejected", reason: LEADERS_SOURCE_REJECTION_MESSAGE };
  }
  throw new Error(`所有权威站点列表抓取失败: ${errors.join(" | ")}`);
}

/**
 * 节点2b（pathA）：随机选一篇 → 抓正文 → 转 Markdown。
 * 选中即从候选列表移出（换源/换篇不重复）；单篇失败（长度过短/抓取异常）记日志后
 * 继续取下一篇，列表耗尽 → 抛错（错误终态）。
 * 续跑恢复（sourceMarkdown 已就绪且非换源重试轮）直接跳过。
 * 成功时写 sourceTitle/sourceUrl/sourceMarkdown + sourceAttempts+1，并把
 * stripQuery(url) 计入 deps.usedUrls（与并发槽位共享的去重集合）。
 */
export async function chooseArticleNode(state: State, deps: NodeDeps): Promise<Update> {
  // 换源重试轮：上一轮 extractFacts 事实卡空（outcome=rejected）→ 重新选篇；
  // 正常续跑（无 outcome 但已有正文）跳过，避免重复抓取
  const retryPick = state.outcome === "rejected" && Boolean(state.sourceMarkdown);
  if (state.sourceMarkdown && !retryPick) return {};
  const usedUrls = deps.usedUrls ?? new Set<string>();
  const entry = (deps.sitesByCategory[state.category] ?? []).find(
    (e) => e.name === state.sourceSiteName,
  );
  if (!entry) {
    throw new Error(`找不到候选列表来源站点: ${state.sourceSiteName}`);
  }
  const errors: string[] = [];
  let leaderSkipped = 0;
  const candidates = [...(state.sourceLinks ?? [])];
  while (candidates.length > 0) {
    const picked = rngPick(candidates, deps.rng);
    // 移出候选：成败都算已尝试，避免再次选中
    const rest = candidates.filter((l) => l.url !== picked.url);
    // 源侧名单过滤(第二段):标题现名 → 直接跳过不抓正文
    if (mentionsCoreLeader(picked.title)) {
      leaderSkipped++;
      log(`chooseArticle: 候选标题含受限人名,跳过 ${picked.url}`);
      candidates.length = 0;
      candidates.push(...rest);
      continue;
    }
    try {
      const article = await entry.adapter.fetchArticle(picked);
      if (article.html.length < 100) {
        errors.push(`${entry.name}: 正文过短(${article.html.length})`);
        candidates.length = 0;
        candidates.push(...rest);
        continue;
      }
      const markdown = td.turndown(article.html).slice(0, SOURCE_MAX_CHARS);
      // 源侧名单过滤(第二段):正文命中 → 换下一篇(标题不带人名但正文现名很常见)
      if (mentionsCoreLeader(`${article.title}\n${markdown}`)) {
        leaderSkipped++;
        log(`chooseArticle: 候选正文含受限人名,跳过 "${article.title}"`);
        candidates.length = 0;
        candidates.push(...rest);
        continue;
      }
      usedUrls.add(stripQuery(article.url));
      log(
        `chooseArticle: [${entry.name}] 选中 "${article.title}" (${article.url}) 正文 ${markdown.length} 字`,
      );
      return {
        sourceTitle: article.title,
        sourceUrl: article.url,
        sourceMarkdown: markdown,
        sourceLinks: rest,
        sourceAttempts: (state.sourceAttempts ?? 0) + 1,
      };
    } catch (e) {
      errors.push(`${entry.name}: ${(e as Error).message}`);
      candidates.length = 0;
      candidates.push(...rest);
    }
  }
  // 候选耗尽：纯名单过滤(无其他失败) → 业务性 rejected；否则技术性 error
  if (leaderSkipped > 0 && errors.length === 0) {
    log(`chooseArticle: 候选全部含受限人名(${leaderSkipped} 篇) -> rejected`);
    return { outcome: "rejected", reason: LEADERS_SOURCE_REJECTION_MESSAGE };
  }
  throw new Error(`候选抓取失败(列表耗尽): ${errors.join(" | ")}`);
}

/** FactSheet 是否为空（源不适配判定）。 */
function isFactSheetEmpty(fs: FactSheet): boolean {
  const words = [fs.who, fs.what, fs.when, fs.where, fs.why, fs.how].filter(Boolean);
  return words.length === 0 && fs.keyNumbers.length === 0;
}

/** extractFacts 参数：maxSourcePicks 仅用于日志轮次文案（默认 3，见 graph.ts）。 */
export type ExtractFactsParams = { maxSourcePicks?: number };

/**
 * 节点3（pathA）：从权威正文抽取 FactSheet。
 * 全部为空 → 源不适配 → outcome=rejected；是否终态由 graph.ts 的 sourceRetryDecision
 * 条件边裁决（空卡且未满 maxSourcePicks → 回 chooseArticle 换篇重抽，封顶才 rejected）。
 */
export async function extractFactsNode(
  state: State,
  deps: NodeDeps,
  params: ExtractFactsParams = {},
): Promise<Update> {
  if (state.factSheet) return {};
  const system = buildFactExtractionSystem();
  const user = buildFactExtractionUser(state.sourceTitle, state.sourceMarkdown);
  const fs = await callLLMStructured(deps.llm, system, user, FactSheet, "extractFacts");
  if (isFactSheetEmpty(fs)) {
    const attempt = state.sourceAttempts ?? 1;
    const maxPicks = params.maxSourcePicks ?? 3;
    log(
      `extractFacts: 事实卡为空（源内容不适配, 第 ${attempt}/${maxPicks} 次）` +
        ` -> ${attempt < maxPicks ? "换篇重试" : "rejected"}`,
    );
    return { outcome: "rejected", reason: REJECTION_MESSAGE };
  }
  log(
    `extractFacts: who="${fs.who}" what="${fs.what}" when="${fs.when}" where="${fs.where}" numbers=[${fs.keyNumbers.join(", ")}] names=[${fs.keyNames.join(", ")}]`,
  );
  return { factSheet: fs };
}

/** 生成器参数（由条件边在路由时决定的路径）。 */
export type GenParams = { path: "A" | "B" };

/**
 * 生成失败分类（catch 里仅凭解析错误对象本身是不够的——信号在模型输出原文上）。
 * 与模型约定：拒答话术（REJECTION_MESSAGE）与 can't_write 结构化信号等价，
 * 都代表"模型判定本主题/来源不可写" → 应换源（generateA 回边）；其余错误
 * （空白/结构/技术）与主题无关 → 保持 error 终态。
 */
export function classifyGenerateFailure(e: unknown): "refused" | "whitespace" | "struct" | "technical" {
  const raw = (e as { llmOutput?: unknown } | null)?.llmOutput;
  if (typeof raw !== "string") return "technical";
  const t = raw.trim();
  if (t === "") return "whitespace";
  if (t === REJECTION_MESSAGE || t.startsWith(REJECTION_MESSAGE)) return "refused";
  return "struct";
}

/**
 * 节点4：生成双语文章。
 * - 输出为 GenerateResult 判别联合：article → 正常返回 draft；cannot_write（模型
 *   判定主题违规/缺依据）→ 业务拒答 rejected + genFailure=refused，由图条件边
 *   路由换源（generateA 回 chooseArticle，B 终态）。
 * - 拒答话术散文（旧形态，模型未按新 schema 拒答时）同样归 refused（兼容识别）。
 * - 其余失败（空白/结构不合规/技术错误）归为 outcome=error（终态），不做自动重试——
 *   重试由用户手动发起（重跑/断点续跑/replay），见 src/replay.ts。
 * - 从 checkpointer 恢复（已有 draft）时跳过重生成；唯一例外是校验违规后的重试轮
 *   （outcome=rejected 且已有旧 draft）——旧 draft 作废重写，lastViolations 由
 *   buildGenerateUserContent 注入为上轮违规反馈。
 */
export async function generateNode(
  state: State,
  deps: NodeDeps,
  params: GenParams,
): Promise<Update> {
  const retryRound = state.outcome === "rejected" && Boolean(state.draft);
  if (state.draft && !retryRound) return {};
  const user = buildGenerateUserContent({
    category: state.category,
    path: params.path,
    sourceTitle: state.sourceTitle ?? "",
    sourceUrl: state.sourceUrl ?? "",
    sourceMarkdown: state.sourceMarkdown ?? "",
    factSheetJson: JSON.stringify(state.factSheet ?? {}),
    lastViolations: state.lastViolations ?? [],
    recentTitles: state.recentTitles ?? [],
  });
  try {
    const result = await callLLMStructured(
      deps.llm,
      buildGenerateSystemPrompt({
        difficulty: state.difficulty,
        category: state.category,
        path: params.path,
      }),
      user,
      GenerateResult,
      `generate${params.path}`,
    );
    if (result.type === "cannot_write") {
      log(`generate${params.path}: 模型拒答（cannot_write）-> rejected`);
      return { outcome: "rejected", reason: REJECTION_MESSAGE, genFailure: "refused" };
    }
    const draft: BilingualArticle = result; // article 变体与 BilingualArticle 同构（多一个 type 字面量）
    const round = (state.genAttempts ?? 0) + 1;
    log(
      `generate${params.path}: 生成成功，${draft.paragraphs.length} 段 (${draft.titleEn.slice(0, 50)})` +
        (retryRound ? ` [第 ${round} 轮重试]` : ""),
    );
    return { draft, genAttempts: round };
  } catch (e) {
    if (classifyGenerateFailure(e) === "refused") {
      // 旧形态兼容：模型未按新 schema 拒答，而是整句输出拒答话术（jsonMode 下解析失败）
      log(`generate${params.path}: 模型拒答（散文话术）-> rejected`);
      return { outcome: "rejected", reason: REJECTION_MESSAGE, genFailure: "refused" };
    }
    // 输出不符合 schema（空白弃答/结构不合规/技术错误）→ 终态 error，需手动重试
    log(`generate${params.path}: 结构校验失败 -> error`);
    return { outcome: "error", reason: `生成结果不符合结构要求: ${(e as Error).message}` };
  }
}

/** 校验参数：path 决定判官组合；maxGenRounds 仅用于日志轮次文案（默认 3）。 */
export type ValidateParams = { path: "A" | "B"; maxGenRounds?: number };

/**
 * 节点5：安全校验（违规 → 图内带反馈自动重试，至多 maxGenRounds 轮含首试；封顶仍违规 →
 * rejected。终态裁决在 graph.ts 的 validateExit 条件边，绕图的 replay/手动调用直接看
 * validateNode 的 return 值）。
 * - pathA：红线判官（带来源全文+日期归因） + 事实一致性判官（带来源全文对照）；
 *   pathB：从严红线判官。
 * - 违规时 lastViolations 记录本轮违规，作为下一轮生成的修正反馈。
 * - 无 draft：上一步生成失败已写 outcome=error，这里原样返回。
 */
export async function validateNode(
  state: State,
  deps: NodeDeps,
  params: ValidateParams,
): Promise<Update> {
  if (!state.draft) return {}; // generateNode 失败已写终态，无需再判

  const runDate = state.runDate;
  const articleJson = JSON.stringify(state.draft);
  const verdicts: SafetyVerdict[] = [];
  if (params.path === "A") {
    verdicts.push(
      await callLLMStructured(
        deps.llm,
        buildRedlineJudgeSystem("A", runDate),
        buildRedlineJudgeUser({
          articleJson,
          sourceTitle: state.sourceTitle ?? "",
          sourceUrl: state.sourceUrl ?? "",
          sourceMarkdown: state.sourceMarkdown ?? "",
          factSheetJson: JSON.stringify(state.factSheet ?? {}),
        }),
        SafetyVerdict,
        "validateA:redline",
      ),
      await callLLMStructured(
        deps.llm,
        buildConsistencyJudgeSystem(runDate),
        buildConsistencyJudgeUser({
          sourceTitle: state.sourceTitle ?? "",
          sourceUrl: state.sourceUrl ?? "",
          factSheetJson: JSON.stringify(state.factSheet ?? {}),
          sourceMarkdown: state.sourceMarkdown ?? "",
          articleJson,
        }),
        SafetyVerdict,
        "validateA:consistency",
      ),
    );
  } else {
    verdicts.push(
      await callLLMStructured(
        deps.llm,
        buildRedlineJudgeSystem("B", runDate),
        buildRedlineJudgeUser({ articleJson }),
        SafetyVerdict,
        "validateB:redline",
      ),
    );
  }

  const violations = verdicts.flatMap((v) => v.violations);
  if (violations.length === 0) {
    log(`validate${params.path}: 通过（检查 ${verdicts.length} 个判官）`);
    return { outcome: "success", lastViolations: [] };
  }
  // 违规：轮数未满 → 由条件边回 generate 带反馈重写；封顶 → 终态 rejected
  const round = state.genAttempts ?? 1;
  const maxRounds = params.maxGenRounds ?? 3;
  const retrying = round < maxRounds;
  log(
    `validate${params.path}: 违规 ${violations.length} 条 (第 ${round}/${maxRounds} 轮)` +
      ` -> ${retrying ? "带反馈重写" : "rejected"}: ${violations
        .map((v) => `[${v.ruleId}] ${v.message.slice(0, 80)}`)
        .join(" | ")}`,
  );
  return { outcome: "rejected", reason: REJECTION_MESSAGE, lastViolations: violations };
}

/** 受限人物名单拒绝话术（区别于通用拒绝话术，便于日志/槽位归因）。 */
export const LEADERS_REJECTION_MESSAGE = "文章提及受限人物名单，已拒绝。";

/** 来源侧名单过滤拒绝话术：候选源全部命中名单时（业务性不适配，非技术失败）。 */
export const LEADERS_SOURCE_REJECTION_MESSAGE = "候选来源均涉及受限人物名单，已拒绝。";

/** 文本命中受限人名名单（含标题/正文的子串匹配，确定性、无 LLM）。 */
export function mentionsCoreLeader(text: string): boolean {
  return memberList.some((name) => text.includes(name));
}

/** 汇总文章全部文本（英文/中文标题 + 每段中英），供受限人名子串匹配。 */
export function collectArticleText(draft: BilingualArticle): string {
  return [
    draft.titleEn,
    draft.titleZh,
    ...draft.paragraphs.flatMap((p: { en: string; zh: string }) => [p.en, p.zh]),
  ].join("\n");
}

/**
 * 节点6（新，无 LLM，A/B 共用）：确定性硬性过滤——文章（标题/段落中英）中出现
 * `src/const/coreLeaders.ts` 名单中的任何姓名 → 立即终态 rejected。
 * 与判官不同：这是名单硬限制，不建议回边重试——设计上视为生成侧违规（pathB 提示词
 * 已明确禁止），宁可整篇拒绝。无 draft（前序已 error）时原样通过，交给 validate 收尾。
 */
export async function coreLeadersNode(state: State, _deps: NodeDeps): Promise<Update> {
  if (!state.draft) return {}; // 前序（如 generate 结构失败）已写终态，无需再判
  const text = collectArticleText(state.draft);
  const hits = memberList.filter((name) => text.includes(name));
  if (hits.length > 0) {
    log(
      `coreLeadersCheck: 命中 ${hits.length} 个受限人名（${hits.join("、").slice(0, 80)}）-> rejected`,
    );
    return { outcome: "rejected", reason: LEADERS_REJECTION_MESSAGE };
  }
  log("coreLeadersCheck: 通过");
  return {};
}

/**
 * 路径判据：类别在权威站点配置（sites.config.ts）中有 ≥1 个站点 → A（有来源支撑），
 * 否则 → B（模型知识）。取代原硬编码 news/expository。
 */
export function resolvePath(
  category: Category,
  sitesByCategory: Partial<Record<Category, SiteEntry[]>>,
): "A" | "B" {
  return (sitesByCategory[category]?.length ?? 0) > 0 ? "A" : "B";
}

/** 条件边 helper：按类别在站点配置中的有无路由 pathA / pathB。 */
export function route(state: State, deps: NodeDeps): "A" | "B" {
  return resolvePath(state.category, deps.sitesByCategory);
}
