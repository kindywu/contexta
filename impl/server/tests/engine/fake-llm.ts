/**
 * 测试专用假 LLM：按 system prompt 特征识别 generate/validate 两类调用，
 * 按预设判定序列驱动图内校验重试；记录每次 generate 收到的 user prompt 原文
 * 以便断言「违规反馈确实带到了下一次请求」。
 * 非测试文件（不含 test()），供 graph-retry / retry 等测试共享。
 */
import { z } from "zod";
import type { AIMessage, BaseMessage } from "@langchain/core/messages";
import type { LLM } from "../../src/engine/llm";
import type { Violation } from "../../src/engine/graph/state";

/** 每次 validate 调用的返回序列；null 表示通过，数组表示违规。 */
export type VerdictSeq = (Violation[] | null)[];

/** FactSheet 造型（与 src/schema.ts 的 FactSheet 对齐，null 表示空卡=源不适配）。 */
export type FactCard = {
  who: string;
  what: string;
  when: string;
  where: string;
  why: string;
  how: string;
  keyNumbers: string[];
  keyNames: string[];
};

export const EMPTY_FACT_CARD: FactCard = {
  who: "", what: "", when: "", where: "", why: "", how: "",
  keyNumbers: [], keyNames: [],
};

export class FakeLLM implements LLM {
  /** 每次 generate 收到的 user prompt 原文（含 feedback 块） */
  generatePrompts: string[] = [];
  validateCalls = 0;
  /** extractFacts 调用次数（事实卡脚本消费） */
  factCalls = 0;

  constructor(
    private readonly verdicts: VerdictSeq,
    /** extractFacts 返回脚本：null=空事实卡（源不适配），FactCard=完整卡；缺省视为未配置 */
    private readonly factCards: (FactCard | null)[] | null = null,
    /** generate 固定返回的英文标题（缺省 "Draft N"），用于构造含敏感人名的草稿 */
    private readonly draftTitleEn?: string,
    /** generate 固定返回的中文标题（缺省 "草稿 N"） */
    private readonly draftTitleZh?: string,
  ) {}

  async invoke(): Promise<AIMessage> {
    throw new Error("FakeLLM 不应被无结构文本调用");
  }

  withStructuredOutput<T>(_schema: z.ZodType<T>) {
    return {
      invoke: async (messages: BaseMessage[]): Promise<T> => this.respond(messages) as T,
    };
  }

  private async respond(messages: BaseMessage[]): Promise<unknown> {
    const sys = String(messages[0]!.content);
    const user = String(messages[1]!.content);
    if (sys.includes("bilingual English-learning article writer")) {
      this.generatePrompts.push(user);
      const n = this.generatePrompts.length;
      return {
        titleEn: this.draftTitleEn ?? `Draft ${n}`,
        titleZh: this.draftTitleZh ?? `草稿 ${n}`,
        paragraphs: [{ en: "EN", zh: "ZH" }],
      };
    }
    if (sys.includes("strict safety compliance reviewer")) {
      const v = this.verdicts[Math.min(this.validateCalls, this.verdicts.length - 1)]!;
      this.validateCalls++;
      return v === null
        ? { passed: true, violations: [] }
        : { passed: false, violations: v };
    }
    if (sys.includes("You extract facts from a news article")) {
      if (!this.factCards) throw new Error("FakeLLM 未配置 factCards 却收到 extractFacts 调用");
      const idx = Math.min(this.factCalls, this.factCards.length - 1);
      this.factCalls++;
      return this.factCards[idx] === null ? EMPTY_FACT_CARD : this.factCards[idx];
    }
    if (sys.includes("fact-consistency reviewer")) {
      return { passed: true, violations: [] }; // path A 一致性判官默认通过
    }
    throw new Error(`FakeLLM 无法识别调用类型: system 前 60 字 = "${sys.slice(0, 60)}"`);
  }
}
