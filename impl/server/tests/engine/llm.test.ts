import { expect, test } from "bun:test";
import { z } from "zod";
import { loadConfig } from "../../src/engine/config";
import { callLLM, callLLMStructured, createLLM } from "../../src/engine/llm";

// 真实访问 DeepSeek 的冒烟测试：需要 .env 里配好 LLM_API_KEY（loadConfig 会校验）
// 走本机代理时单次调用可能耗时较长，给足 60s 超时
test("真实调用 LLM：纯文本 + 结构化输出", async () => {
  const llm = createLLM(loadConfig());

  const text = await callLLM(llm, "你是测试助手", "请只回复两个字：收到");
  console.log(`callLLM → ${text}`);
  expect(text).toBeTruthy();

  const FactSheet = z.object({
    标题: z.string().min(1),
    亮点: z.array(z.string()),
  });
  const structured = await callLLMStructured(
    llm,
    "从下面句子抽取文章信息，不要输出多余内容",
    "这是一篇介绍 Bun 1.4 的文章，亮点是内置了 HTTP proxy 支持。",
    FactSheet,
  );
  console.log(`callLLMStructured → ${JSON.stringify(structured)}`);
  expect(structured.标题).toBeTruthy();
}, 60_000);
