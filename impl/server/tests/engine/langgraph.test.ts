import { expect, test } from "bun:test";
import { Annotation, StateGraph, START, END } from "@langchain/langgraph";
import { loadConfig } from "../../src/engine/config";
import { callLLM, createLLM } from "../../src/engine/llm";

/**
 * 最简单的 LangGraph DAG 测试，验证 langgraph 在本项目里能跑通：
 *   START → llmNode（调 DeepSeek 生成一句话草稿，真实 LLM 调用）
 *          → formatNode（本地整理，不调 LLM）
 *          → END
 * 需要 .env 里配好 LLM_API_KEY（loadConfig 会校验）；走本机代理时单次调用
 * 可能较慢，给足 60s 超时。
 */
test("LangGraph DAG：LLM 节点 + 本地节点", async () => {
  const llm = createLLM(loadConfig());

  // state：节点返回的字段按 key 覆盖同名值（Annotation 默认 LastValue reducer）
  const State = Annotation.Root({
    topic: Annotation<string>,
    draft: Annotation<string>,
    final: Annotation<string>,
  });

  const graph = new StateGraph(State)
    .addNode("llmNode", async (state: typeof State.State) => {
      const draft = await callLLM(llm, "你是一个文章助手，请用一句话写短评", state.topic);
      return { draft };
    })
    .addNode("formatNode", async (state: typeof State.State) => ({
      final: `【主题】${state.topic}\n【短评】${state.draft}`,
    }))
    .addEdge(START, "llmNode")
    .addEdge("llmNode", "formatNode")
    .addEdge("formatNode", END)
    .compile();

  const out = await graph.invoke({ topic: "Bun 1.4 内置了 HTTP 代理支持" });
  console.log(out);
  expect(out.draft).toBeTruthy();
  expect(out.final).toContain("【主题】");
  expect(out.final).toContain(out.draft);
}, 60_000);
