/**
 * 选题规划与批次内选题去重（pickTopic 节点用）。
 *
 * 背景（2026-09-17 事故）：生成 prompt 只给类别与难度、不给选题，模型对"写什么"有完全
 * 自由——LOW/simple_story 的选题分布极度集中（雨天/公交站/雨伞、拿错东西、写信寄错），
 * 同批并发槽位的 prompt 又完全相同（仅 threadId 不同、不进 prompt），于是 2026-09-17
 * 三篇 simple_story 全部产出"伞文"（The Yellow/Blue/Wrong Umbrella），daily_conversation
 * 槽位也撞在伞上。既有的"近期标题"软约束救不了：它是负向提示（"别写这些"），且批内兄弟
 * 槽位互相看不见。
 *
 * 本模块的对策：**先定选题再写作**——pickTopic 节点经 `TopicRegistry` 串行取号，
 * 规划一个与近期已发布文章、且与同批其他槽位都不同的选题，注入生成 prompt。
 */
import type { Category, Difficulty } from "../schema";
import { TopicPlan } from "../schema";
import { callLLMStructured, type LLM } from "../llm";
import { buildTopicPlannerSystem, buildTopicPlannerUser } from "./prompts";
import { log } from "./log";

/**
 * 选题相似度阈值：内容词 Jaccard 系数 ≥ 1/3 判为重复选题。
 * 取 1/3 而非更高值，是为了拦住"只换修饰语"这一最低劣的重复形态——
 * "The Yellow Umbrella" 与 "The Blue Umbrella" 的 Jaccard 恰为 1/3（共用 umbrella），
 * 阈值更高就漏判；再低则会把"共用一个普通词（lost/old/first）"的不同题材也算重复。
 */
export const SIMILARITY_NUMERATOR = 1;
export const SIMILARITY_DENOMINATOR = 3;

/** 选题短语长度上限（字符）：超长多半是模型把整段设定写进来了，判为无效。 */
const MAX_TOPIC_CHARS = 200;

/** 规划尝试次数上限（含首试）：一次给"选题重复"，一次给技术失败。 */
const PLANNER_ATTEMPTS = 2;

/** 参与相似度判定的停用词：功能词 + 选题里的高频填充词（不承载题材信息）。 */
const STOPWORDS = new Set([
  "the", "and", "for", "with", "from", "into", "over", "under", "about", "after",
  "before", "between", "during", "without", "his", "her", "its", "their", "our",
  "your", "she", "him", "they", "them", "you", "who", "whose", "what", "when",
  "where", "why", "how", "that", "this", "these", "those", "there", "then", "than",
  "are", "was", "were", "been", "being", "has", "have", "had", "does", "did",
  "doing", "done", "but", "not", "also", "one", "two", "first", "new", "old",
  "day", "days", "time", "story", "article", "made", "make", "makes", "takes",
  "gets",
]);

/** 抽内容词：小写、非字母转空格、去停用词与 1-2 字母词（"a"/"an"/"of"…）。 */
export function contentWords(text: string): Set<string> {
  const words = text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .split(" ")
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w));
  return new Set(words);
}

/**
 * 两个选题是否雷同：内容词 Jaccard 系数 ≥ 1/3（十字相乘比较，避开浮点边界）。
 * 判定是确定性的——只换修饰语（黄伞/蓝伞/拿错的伞）、同场景换人物物件
 * （"女孩在车站捡到走失的小狗" vs "男孩在车站捡到走失的小猫"）都会被拦住，
 * 而共用个别普通词的不同题材不会误伤。
 */
export function isSimilarTopic(a: string, b: string): boolean {
  const wa = contentWords(a);
  const wb = contentWords(b);
  if (wa.size === 0 || wb.size === 0) return false; // 无内容词：交给长度校验处理
  let hit = 0;
  for (const w of wa) if (wb.has(w)) hit++;
  const union = wa.size + wb.size - hit;
  return hit * SIMILARITY_DENOMINATOR >= union * SIMILARITY_NUMERATOR;
}

/**
 * 一轮生成内共享的选题登记簿（与 `usedUrls` 同层：进程内共享、每 run 一个）。
 *
 * 并发语义：`reserve` 把「看已占快照 → 调 LLM 规划 → 登记」整段串行化。若只锁登记
 * 不锁规划，两个并发槽位会各自看到同一份空快照、各自规划出雷同选题——正是事故成因。
 * 规划本身是 LLM 调用（秒级），串行带来的等待由槽位并发度吸收（一槽规划时其余槽照常
 * 生成/抓取），不构成瓶颈。
 */
export class TopicRegistry {
  private taken: string[] = [];
  private chain: Promise<unknown> = Promise.resolve();

  /** 已占用选题快照（诊断/日志用）。 */
  snapshot(): readonly string[] {
    return [...this.taken];
  }

  /**
   * 串行预约一个选题：`plan` 收到当前已占快照，返回的选题非空则登记进簿。
   * `plan` 抛错只影响本槽位（后续槽位继续排队，不受污染）。
   */
  reserve(plan: (taken: readonly string[]) => Promise<string | undefined>): Promise<string | undefined> {
    const run = this.chain.then(async () => {
      const topic = await plan(this.snapshot());
      if (topic) this.taken.push(topic);
      return topic;
    });
    // 链上只记录"上一槽已完成"，不传播异常——单槽规划失败不得卡住整批取号
    this.chain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
}

/** 选题校验：空/超长/与已用（近期标题 + 本批已占选题）雷同 → 返回拒绝原因。 */
export function validateTopic(
  topic: string,
  used: readonly string[],
): string | undefined {
  if (topic.length === 0) return "选题为空";
  if (topic.length > MAX_TOPIC_CHARS) return `选题过长（${topic.length} 字符）`;
  const clash = used.find((u) => isSimilarTopic(topic, u));
  return clash ? `与已用题材雷同（"${clash}"）` : undefined;
}

export interface PlanTopicArgs {
  llm: LLM;
  runDate: string;
  difficulty: Difficulty;
  category: Category;
  /** 近期（近 5 天）已发布文章标题 */
  recentTitles: string[];
  /** 本轮已分配给其他槽位的选题（TopicRegistry 快照） */
  takenTopics: string[];
  /** 尝试次数上限（含首试），缺省 2 */
  attempts?: number;
}

/**
 * 为单个槽位规划选题。**永不抛错**：任何失败（LLM 异常、输出不合规、规划不出不重复的
 * 选题）都返回 undefined，由调用方退回"模型自由选题"（即改造前的行为）——选题规划是
 * 提升多样性的增强，不得变成新的生成故障点。
 */
export async function planTopic(args: PlanTopicArgs): Promise<string | undefined> {
  const { llm, runDate, difficulty, category, recentTitles, takenTopics } = args;
  const attempts = args.attempts ?? PLANNER_ATTEMPTS;
  const used = [...recentTitles, ...takenTopics];
  let rejected: string | undefined;

  for (let attempt = 1; attempt <= attempts; attempt++) {
    let raw: TopicPlan;
    try {
      raw = await callLLMStructured(
        llm,
        buildTopicPlannerSystem(),
        buildTopicPlannerUser({
          runDate, difficulty, category, recentTitles, takenTopics,
          ...(rejected ? { rejectedTopic: rejected } : {}),
        }),
        TopicPlan,
        "pickTopic",
      );
    } catch (e) {
      log(
        `pickTopic: 规划调用失败（第 ${attempt}/${attempts} 轮）: ` +
          `${e instanceof Error ? e.message : String(e)}`,
      );
      continue;
    }
    const topic = raw.topic.trim();
    const problem = validateTopic(topic, used);
    if (!problem) return topic;
    rejected = topic;
    log(`pickTopic: 第 ${attempt}/${attempts} 轮选题被拒（${problem}）: "${topic}"`);
  }
  return undefined;
}
