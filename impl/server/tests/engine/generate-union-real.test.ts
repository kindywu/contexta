/**
 * GenerateResult（判别联合：article | cannot_write）的真实模型验收测试。
 *
 * 为什么必须真模型：整个设计依赖 deepseek-v4-flash 在该 prompt 下真的会按
 * 结构化 schema 输出两种变体、并在受限主题下输出拒答变体——fake LLM 测不到
 * 模型行为（今天 whitespace 案例即 fake 全绿、真机打脸）。
 *
 * 模型特性容忍：64k 预算下该 prompt 仍有约 25% 空白弃答（finish=stop、
 * content 纯空白），与"模型判定可写/拒答"无关。故每个测试内部最多尝试
 * N 次，只断言"能力存在性"（至少一次命中目标变体），空白次数记入日志不判 fail。
 *
 * 成本：真 DeepSeek 调用，单测试 1-4 次生成（约 30-200s）；依赖 .env 里
 * LLM_API_KEY（loadConfig 校验，同 langgraph.test.ts）。
 */
import { expect, test } from "bun:test";
import { loadConfig } from "../../src/engine/config";
import { createLLM } from "../../src/engine/llm";
import { generateNode, type NodeDeps } from "../../src/engine/graph/nodes";
import type { ArticleGenState } from "../../src/engine/graph/state";
import type { GeneratedArticle } from "../../src/engine/graph/state";
import { memberList } from "../../src/engine/const/coreLeaders";

const cfg = loadConfig();
const deps: NodeDeps = { llm: createLLM(cfg), sitesByCategory: {}, rng: () => 0 };

/** 构造 generateNode 输入状态（path A，正文+事实卡齐全）。 */
function baseState(overrides: Partial<typeof ArticleGenState.State> = {}): typeof ArticleGenState.State {
  return {
    runDate: "2026-08-31",
    difficulty: "MEDIUM",
    category: "expository",
    sourceSiteName: "chinadaily",
    sourceLinks: [],
    sourceAttempts: 1,
    sourceTitle: "The Water Cycle: Nature's Recycling Engine",
    sourceUrl: "https://example.com/water-cycle",
    sourceMarkdown:
      "The water cycle describes how water moves between oceans, rivers, and the sky. Water evaporates from warm seas, forms clouds, and falls back as rain. Ice sheets store frozen water for centuries. This process has powered Earth's weather for billions of years.",
    factSheet: {
      who: "",
      what: "water cycle and its stages",
      when: "",
      where: "Earth",
      why: "solar energy drives evaporation",
      how: "condensation and precipitation",
      keyNumbers: [],
      keyNames: [],
    },
    recentTitles: [],
    recentUsedUrls: [],
    ...overrides,
  } as unknown as typeof ArticleGenState.State;
}

/** 执行一次 generateNode；空白弃答（error + 原内容为纯空白）返回 null，其余返回更新。 */
async function attemptOnce(state: typeof ArticleGenState.State): Promise<Partial<typeof ArticleGenState.State> | null> {
  const out = await generateNode(state, deps, { path: "A" });
  if (out.outcome === "error") return null; // whitespace/struct：本轮视为弃答，重试
  return out;
}

test("正常主题：模型能返回 article 变体（结构化生成成功）", async () => {
  for (let i = 1; i <= 4; i++) {
    const out = await attemptOnce(baseState());
    if (!out) {
      console.log(`[${i}/4] 空白弃答，重试`);
      continue;
    }
    expect(out.draft).toBeDefined();
    const draft = out.draft as unknown as GeneratedArticle;
    expect(draft.titleEn.length).toBeGreaterThan(0);
    expect(draft.titleZh.length).toBeGreaterThan(0);
    expect(draft.paragraphs.length).toBeGreaterThan(0);
    return;
  }
  expect.unreachable("连续 4 次空白弃答（概率 ~0.4%），请检查模型/预算");
}, 300_000);

test("受限人物主题：模型结构化拒答（cannot_write 或散文话术）→ 程序判 rejected + genFailure=refused", async () => {
  const name = memberList[0]!;
  const state = baseState({
    sourceTitle: "Recent Speech by a Political Figure",
    sourceUrl: "https://example.com/speech",
    sourceMarkdown: `A recent speech by ${name} emphasized unity and development. The figure called for new industrial policies at a national meeting.`,
    factSheet: {
      who: name,
      what: "recent speech",
      when: "",
      where: "China",
      why: "",
      how: "",
      keyNumbers: [],
      keyNames: [name],
    },
  });
  for (let i = 1; i <= 4; i++) {
    const out = await attemptOnce(state);
    if (!out) {
      console.log(`[${i}/4] 空白弃答，重试`);
      continue;
    }
    if (out.draft) {
      console.log(`[${i}/4] 模型未拒答（写出来了，leader 内容交由 leadersCheck 拦），继续重试`);
      continue;
    }
    expect(out.outcome).toBe("rejected");
    expect(out.genFailure).toBe("refused");
    return;
  }
  expect.unreachable(`受限人物主题 4 次尝试均未产生拒答判定（概率低），模型行为异常`);
}, 300_000);
