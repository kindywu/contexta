import { expect, test } from "bun:test";
import { Annotation, StateGraph, START, END } from "@langchain/langgraph";
import { ArticleGenState } from "../../src/engine/graph/state";

/** 不调 LLM：两个纯节点，验证新输入字段随 state 流转。 */
test("ArticleGenState: recentTitles/recentUsedUrls 作为输入传入并可读", async () => {
  const graph = new StateGraph(ArticleGenState)
    .addNode("read", async (s: typeof ArticleGenState.State) => ({
      reason: `titles=${s.recentTitles?.length ?? -1};urls=${s.recentUsedUrls?.length ?? -1}`,
      outcome: "success",
    }))
    .addEdge(START, "read")
    .addEdge("read", END)
    .compile();

  const out = await graph.invoke({
    runDate: "2026-08-29",
    difficulty: "LOW",
    recentTitles: ["t1", "t2"],
    recentUsedUrls: ["https://a.com/x"],
  });
  expect(out.reason).toBe("titles=2;urls=1");

  // 缺省传入 → 未定义（消费方需 ?? []）
  const out2 = await graph.invoke({ runDate: "2026-08-29", difficulty: "LOW" });
  expect(out2.reason).toBe("titles=-1;urls=-1");
});
