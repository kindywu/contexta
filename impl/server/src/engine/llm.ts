import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import type { AIMessage, BaseMessage } from "@langchain/core/messages";
import type { ChatGeneration, LLMResult } from "@langchain/core/outputs";
import { z } from "zod";
import type { AppConfig } from "./config";
import { log } from "./graph/log";

/**
 * 业务代码只依赖这个最小接口，测试通过注入假 LLM 在此 seam 上验证行为。
 * 真实实现由 createLLM() 给出（LangChain ChatOpenAI）。
 */
export interface LLM {
  invoke(messages: BaseMessage[], options?: unknown): Promise<AIMessage>;
  /** 结构化输出：模型侧按 schema 生成并校验 JSON，返回类型化结果。 */
  withStructuredOutput<T>(
    schema: z.ZodType<T>,
    options?: { method?: string },
  ): {
    invoke(messages: BaseMessage[], options?: unknown): Promise<T>;
  };
}

/** 单轮文本调用：system + user → 模型回复的纯文本。label 用于日志里标识步骤。 */
export async function callLLM(
  llm: LLM,
  system: string,
  user: string,
  label = "llm",
): Promise<string> {
  logPrompt(label, system, user);
  const res = await llm.invoke(
    [new SystemMessage(system), new HumanMessage(user)],
    { callbacks: [responseLogCallback(label)] },
  );
  return extractText(res.content);
}

/**
 * 按配置构造 ChatOpenAI（baseURL 指向 DeepSeek 或任意 OpenAI 兼容网关）。
 * maxTokens 必须显式给足：deepseek-v4-flash 为思考模型，reasoning_content 消耗输出预算；
 * 缺省上限过小时（实测同批 article 生成任务思考 2.8 万字符）思考把预算吃光，
 * content 只剩空白 → jsonMode 解析失败（"Text: ' '" + Unexpected EOF）。32000 为实测可完成值。
 */
export function createLLM(cfg: AppConfig): ChatOpenAI {
  return new ChatOpenAI({
    model: cfg.llmModel,
    apiKey: cfg.llmApiKey,
    configuration: {
      baseURL: cfg.llmBaseUrl,
      ...(cfg.proxyUrl ? { fetch: makeProxyFetch(cfg.proxyUrl) } : {}),
    },
    maxTokens: 64_000,
  });
}

/** 配置了代理时，给 OpenAI SDK 换个走代理的 fetch（Bun 原生 proxy 选项）。 */
function makeProxyFetch(proxyUrl: string) {
  return (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => fetch(input, { ...init, proxy: proxyUrl });
}

/**
 * 结构化单轮调用：system + user + zod schema → 类型化结果。
 * label 用于日志里标识步骤（如 extractFacts / generateA / validateA:consistency）。
 */
export async function callLLMStructured<T>(
  llm: LLM,
  system: string,
  user: string,
  schema: z.ZodType<T>,
  label = "llm",
): Promise<T> {
  const schemaDoc = JSON.stringify(z.toJSONSchema(schema));
  const jsonOnly =
    `${system}\n请只输出符合以下 json 结构的 json 对象，字段名与类型完全一致，` +
    `不要输出其他内容：\n${schemaDoc}`;
  // DeepSeek：思考模式不支持 tool_choice（functionCalling），也不认 jsonSchema；
  // 只能 json_object（jsonMode）且提示词必须含 "json" 字样；ChatOpenAI 的 jsonMode
  // 不会把 schema 注入提示词，需要我们自己写进去
  logPrompt(label, jsonOnly, user);
  return llm
    .withStructuredOutput(schema, { method: "jsonMode" })
    .invoke(
      [new SystemMessage(jsonOnly), new HumanMessage(user)],
      { callbacks: [responseLogCallback(label)] },
    );
}

/**
 * 把实际发给模型的 system + user 原文写进日志（含结构化调用注入的 json schema），便于核对 prompt。
 * 摘要行恒记（info）；全文默认隐藏，--log-level debug 才输出（全文体积大，按需开启）。
 */
function logPrompt(label: string, system: string, user: string): void {
  log(`llm[${label}] 请求: system ${system.length} 字符, user ${user.length} 字符`);
  log(`system:\n${system}`, "debug");
  log(`user:\n${user}`, "debug");
}

/**
 * LLM 响应留痕（生成结束即触发——即使后续 jsonMode 解析失败，原始响应也已落盘）。
 * info 记摘要（finish_reason/用量/长度），debug 记原文与思考内容。
 * 背景：deepseek-v4-flash 为思考模型，失败现场全在响应里（如 content 只剩空白、
 * reasoning_content 占满预算），此前不记录导致无法复盘，只能靠报错里的 Text 反推。
 */
function responseLogCallback(label: string) {
  return {
    handleLLMEnd: (output: LLMResult) => {
      const msg = (output.generations?.[0]?.[0] as ChatGeneration | undefined)?.message;
      const text = extractText(msg?.content ?? "");
      const ac = msg?.additional_kwargs as Record<string, unknown> | undefined;
      const reasoning = ac?.reasoning_content ?? ac?.reasoning;
      const meta = (output.llmOutput ?? {}) as Record<string, unknown>;
      const usage = (meta.tokenUsage ?? meta.usage ?? {}) as Record<string, unknown>;
      log(
        `llm[${label}] 完成: finish=${meta.finishReason ?? "?"} ` +
          `tokens=${JSON.stringify(usage)} content=${text.length}字符 ` +
          `reasoning=${typeof reasoning === "string" ? reasoning.length : "?"}字符`,
      );
      log(`llm[${label}] 响应: ${text}`, "debug");
      if (typeof reasoning === "string" && reasoning.length > 0) {
        log(`llm[${label}] 思考: ${reasoning}`, "debug");
      }
    },
  };
}

/** AIMessage 的 content 可能是字符串或分段数组，这里统一压成纯文本。 */
function extractText(content: AIMessage["content"]): string {
  if (typeof content === "string") return content;
  return content
    .map((part) =>
      typeof part === "string" ? part : part.type === "text" ? part.text : "",
    )
    .join("");
}
