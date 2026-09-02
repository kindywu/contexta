import { END, START, StateGraph } from "@langchain/langgraph";
import type { BaseCheckpointSaver, RetryPolicy } from "@langchain/langgraph";
import {
  chooseArticleNode,
  coreLeadersNode,
  extractFactsNode,
  fetchLinksNode,
  generateNode,
  LEADERS_REJECTION_MESSAGE,
  LEADERS_SOURCE_REJECTION_MESSAGE,
  pickCategoryNode,
  resolvePath,
  route,
  validateNode,
  type NodeDeps,
} from "./nodes";
import { ArticleGenState } from "./state";

export interface BuildGraphOptions {
  deps: NodeDeps;
  /** 运行时重试策略（瞬时故障兜底；见 buildArticleGraph 注释），默认 3 次。 */
  retryPolicy?: RetryPolicy;
  /** 断点续跑的 checkpointer（通常为 src/graph/checkpointer.ts 的 BunSqliteCheckpointer）。 */
  checkpointer?: BaseCheckpointSaver;
  /** 校验违规后的生成轮数上限（含首试），默认 3：违规即带反馈回边重写，封顶仍违规 → rejected。 */
  maxGenRounds?: number;
  /** 源抽取轮数上限（含首试），默认 3：extractFacts 空卡（源不适配）即回 chooseArticle 换篇重抽，封顶仍空 → rejected。 */
  maxSourcePicks?: number;
}

/**
 * 校验违规重试判定（validateA/validateB 共用）：违规且轮数未满 → 回 generate
 * 带违规反馈重写；轮数封顶或已通过 → 终态结束。genAttempts 由 generate 节点递增，
 * 首试 = 1。
 */
export function shouldRetryValidate(
  state: Pick<typeof ArticleGenState.State, "outcome" | "genAttempts">,
  maxGenRounds: number,
): boolean {
  return state.outcome === "rejected" && (state.genAttempts ?? 0) < maxGenRounds;
}

/** validateA/validateB 的共同出口：重试或在 END 收尾。 */
function validateExit(path: "A" | "B", maxGenRounds: number) {
  return (s: typeof ArticleGenState.State) =>
    shouldRetryValidate(s, maxGenRounds) ? `generate${path}` : "done";
}

/**
 * extractFacts 之后的源换篇判定：事实卡非空 → 进入生成；空卡且抽取轮数未满
 * maxSourcePicks → 回 chooseArticle 换一篇重抽（不重抓列表）；轮数封顶 → 终态。
 * sourceAttempts 由 chooseArticleNode 在抓正文成功时递增（首试 = 1）。
 */
export function sourceRetryDecision(
  state: Pick<typeof ArticleGenState.State, "outcome" | "factSheet" | "sourceAttempts">,
  maxSourcePicks: number,
): "retry" | "next" | "done" {
  if (state.factSheet) return "next"; // 抽取成功 → 进入生成
  if (state.outcome === "rejected" && (state.sourceAttempts ?? 0) < maxSourcePicks) {
    return "retry";
  }
  return "done";
}

/**
 * 组装文章生成图（设计见 docs/ 目录下的设计记录）：
 *
 *   START → pickCategory -(类别)→ A: fetchLinks → chooseArticle → extractFacts → generateA → validateA → END
 *                                └──────────── B(其余9类):  generateB → validateB → END
 *   generateA/B 模型拒答（genFailure=refused）→ A 回 chooseArticle、B 短路（见下方回边说明）
 *
 * 业务回边/短路（默认 3 轮含首试，可注入）：
 * - extractFacts 空卡（源不适配）→ 回 chooseArticle 换篇重抽（不重抓列表），封顶 → rejected；
 * - generate 拒答（模型判主题/来源不可写，genFailure=refused）→ A 回 chooseArticle 换篇
 *   （sourceAttempts 封顶 → 短路 rejected）；B 无源可换 → 短路 rejected；
 * - validate 违规 → 回 generate 带违规反馈重写，封顶 → rejected。
 * 其余失败（生成空白/结构畸形、技术错误）统一 error 终态，不走回边（用户拍板：不自动重试）。
 * 瞬时故障由 setNodeDefaults retryPolicy 兜底；手动重试入口见 src/replay.ts。
 * 节点工厂按路径参数化，A/B 各注册一份实例（generateA/generateB/validateA/validateB），
 * 实现共用 generateNode/validateNode，避免两份硬代码。
 */
export function buildArticleGraph(options: BuildGraphOptions) {
  const { deps, retryPolicy, checkpointer } = options;
  const maxGenRounds = options.maxGenRounds ?? 3;
  const maxSourcePicks = options.maxSourcePicks ?? 3;
  const graph = new StateGraph(ArticleGenState)
    .setNodeDefaults({ retryPolicy: retryPolicy ?? { maxAttempts: 3 } })
    .addNode("pickCategory", (s) => pickCategoryNode(s, deps))
    .addNode("fetchLinks", (s) => fetchLinksNode(s, deps))
    .addNode("chooseArticle", (s) => chooseArticleNode(s, deps))
    .addNode("extractFacts", (s) => extractFactsNode(s, deps, { maxSourcePicks }))
    .addNode("generateA", (s) => generateNode(s, deps, { path: "A" }))
    .addNode("generateB", (s) => generateNode(s, deps, { path: "B" }))
    .addNode("leadersCheck", (s) => coreLeadersNode(s, deps))
    .addNode("validateA", (s) => validateNode(s, deps, { path: "A", maxGenRounds }))
    .addNode("validateB", (s) => validateNode(s, deps, { path: "B", maxGenRounds }))
    .addEdge(START, "pickCategory")
    .addConditionalEdges("pickCategory", (s) => route(s, deps), {
      A: "fetchLinks",
      B: "generateB",
    })
    // fetchLinks/chooseArticle 可能因名单过滤耗尽而业务性 rejected（state.reason 区分），
    // 短路收尾；stale rejected（extractFacts 换篇重试轮留下的）不短路，继续抽取
    .addConditionalEdges(
      "fetchLinks",
      (s) =>
        s.outcome === "rejected" && s.reason === LEADERS_SOURCE_REJECTION_MESSAGE
          ? "done"
          : "chooseArticle",
      { done: END, chooseArticle: "chooseArticle" },
    )
    .addConditionalEdges(
      "chooseArticle",
      (s) =>
        s.outcome === "rejected" && s.reason === LEADERS_SOURCE_REJECTION_MESSAGE
          ? "done"
          : "extractFacts",
      { done: END, extractFacts: "extractFacts" },
    )
    // extractFacts 空卡（源不适配）且未满轮数 → 回 chooseArticle 换篇重抽，不重抓列表；
    // 抽取成功 → 生成；封顶仍空 → 短路收尾（rejected）
    .addConditionalEdges(
      "extractFacts",
      (s) => {
        const d = sourceRetryDecision(s, maxSourcePicks);
        return d === "retry" ? "retrySource" : d === "next" ? "generate" : "done";
      },
      { retrySource: "chooseArticle", generate: "generateA", done: END },
    )
    // 生成后先过受限人名硬检查（无 LLM）：命中即终态 rejected（短路收尾）；
    // 未命中（outcome 未写）按路径分流到对应判官
    // 生成侧业务拒答（genFailure=refused，模型判"本主题/来源不可写"）路由：
    // - A 有源可换 → 回 chooseArticle 换篇重抽（sourceAttempts 封顶 → 短路 rejected）；
    // - B 无源可换 → 短路终态 rejected；
    // - 其余（success / error 终态）原路走 leadersCheck。
    // 注意：draft 存在时一律不过这里（换源轮后成功生成，stale refused 走正常流程）。
    .addConditionalEdges(
      "generateA",
      (s) =>
        s.genFailure === "refused" && !s.draft
          ? (s.sourceAttempts ?? 0) < maxSourcePicks
            ? "retrySource"
            : "done"
          : "next",
      { retrySource: "chooseArticle", done: END, next: "leadersCheck" },
    )
    .addConditionalEdges(
      "generateB",
      (s) => (s.genFailure === "refused" && !s.draft ? "done" : "next"),
      { done: END, next: "leadersCheck" },
    )
    .addConditionalEdges(
      "leadersCheck",
      (s) =>
        // 仅「本节点自己判 reject」短路；validate 违规留下的 stale outcome=rejected
        // （重写轮中）必须继续走判官流程，由 validate 覆盖 outcome
        s.outcome === "rejected" && s.reason === LEADERS_REJECTION_MESSAGE
          ? "done"
          : resolvePath(s.category, deps.sitesByCategory),
      { done: END, A: "validateA", B: "validateB" },
    )
    // 违规且未到轮数上限 → 带回违规反馈重写；通过/封顶（或 error）→ 终态收尾
    .addConditionalEdges("validateA", validateExit("A", maxGenRounds), {
      generateA: "generateA",
      done: END,
    })
    .addConditionalEdges("validateB", validateExit("B", maxGenRounds), {
      generateB: "generateB",
      done: END,
    });
  // 瞬时故障兜底（网络抖动/5xx）由 setNodeDefaults 的 retryPolicy 提供：
  // 单节点最多重试 3 次；欠费等持续失败仍会抛出，由 generateArticle 层归为
  // outcome=error。
  // checkpointer 为空则不落盘（断点续跑功能关闭）。
  return graph.compile({ ...(checkpointer ? { checkpointer } : {}) });
}
