/**
 * 步骤级重放/手动重试工具：只重跑「生成 generate」和「校验 validate」，不复用图中别的节点
 * （不重抓来源、不重抽事实卡）。图内已有带反馈的校验自动重写（默认 3 轮封顶），
 * 这里是被拒后继续人工处置（超越封顶）的入口。
 *
 * 为什么需要：全流程重跑会重新随机选类别/重抓站点，数据（来源、事实卡）可能已经变了；
 * 而 LangGraph checkpointer（data/langgraph.sqlite）里按 threadId 存了每个步骤的完整
 * 输入输出（sourceMarkdown/factSheet/draft/lastViolations），从它恢复状态，
 * 再直接调 generateNode/validateNode 即可。日志文件只有摘要行，不足以重放。
 *
 * 用法：
 *   bun src/replay.ts --thread <id>                    # 带着上次违规反馈重新生成 + 校验
 *   bun src/replay.ts --thread <id> --mode validate    # 只重跑校验（用 checkpoint 里的旧 draft）
 *   bun src/replay.ts --thread <id> --mode generate    # 只重新生成（不看判官）
 *   bun src/replay.ts --thread <id> --fresh            # 清掉 lastViolations 反馈，模拟首次生成
 *   bun src/replay.ts --thread <id> --log-level debug  # 记录完整 prompt（默认 info 只记摘要）
 *
 * 注意：本项目给 DeepSeek 用的是 jsonMode，Bun 直接运行 TS，无需编译。
 */

import { mkdirSync, appendFileSync } from "node:fs";
import { join } from "node:path";
import { assertSystemTimezone, loadConfig } from "./config";
import { createLLM } from "./llm";
import { generateNode, validateNode, type NodeDeps } from "./graph/nodes";
import { BunSqliteCheckpointer } from "./graph/checkpointer";
import { ArticleGenState } from "./graph/state";
import { redirectLogFile, setLogLevel } from "./graph/log";
import { localFileStamp, localTimestamp } from "./utils/time";

function parseArgs(argv: string[]): {
  threadId: string;
  mode: "both" | "generate" | "validate";
  fresh: boolean;
  logLevel: "info" | "debug";
} {
  let threadId: string | undefined;
  let mode: "both" | "generate" | "validate" = "both";
  let fresh = false;
  let logLevel: "info" | "debug" = "info";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "--thread") threadId = argv[i + 1];
    else if (a === "--mode") {
      const m = argv[i + 1];
      if (m === "generate" || m === "validate" || m === "both") mode = m;
      else throw new Error(`--mode 只支持 generate|validate|both，收到 ${m}`);
    } else if (a === "--fresh") fresh = true;
    else if (a === "--log-level") {
      const l = argv[i + 1];
      if (l === "info" || l === "debug") logLevel = l;
      else throw new Error(`--log-level 只支持 info|debug，收到 ${l}`);
    }
  }
  if (!threadId) throw new Error("缺少 --thread <threadId>（用 --resume manual-xxxx 的同一个 id）");
  return { threadId, mode, fresh, logLevel };
}

/** 从 checkpointer 恢复该 thread 的 state（channel_values），供节点直接调用。 */
async function loadState(threadId: string): Promise<Record<string, unknown>> {
  const cfg = loadConfig();
  const cp = new BunSqliteCheckpointer(cfg.checkpointPath);
  const tuple = await cp.getTuple({ configurable: { thread_id: threadId } });
  if (!tuple) throw new Error(`没找到 threadId=${threadId} 的 checkpoint`);
  // langgraph 新版 checkpoint 字段是 channel_values（旧版兼容别名 values）
  const checkpoint = tuple.checkpoint as unknown as {
    channel_values?: Record<string, unknown>;
    values?: Record<string, unknown>;
  };
  const state =
    checkpoint.channel_values ??
    checkpoint.values ??
    {};
  if (!state.sourceMarkdown || !state.factSheet) {
    throw new Error("checkpoint 里缺少 sourceMarkdown/factSheet，无法重放（该 thread 还没走到抓取/抽卡？）");
  }
  return state;
}

/** 重放日志：单独文件，不混入 run-*.log（命名与时间戳均取配置时区本地时刻）。 */
function initReplayLog(timeZone?: string): string {
  mkdirSync("logs", { recursive: true });
  return join("logs", `replay-${localFileStamp(timeZone)}.log`);
}

async function main() {
  const { threadId, mode, fresh, logLevel } = parseArgs(process.argv.slice(2));
  const cfg = loadConfig();
  assertSystemTimezone(cfg.timezone); // 启动校验：配置时区与系统时区不一致 → 拒绝运行
  const logPath = initReplayLog(cfg.timezone);
  // llm.ts 的全局 log() 也切到本文件：节点内发出去的 prompt 原文一并落盘
  redirectLogFile(logPath);
  setLogLevel(logLevel);
  const replayLog = (msg: string) => {
    const line = `[${localTimestamp(cfg.timezone)}] ${msg}`;
    console.log(line);
    appendFileSync(logPath, line + "\n");
  };

  const raw = await loadState(threadId);
  const deps: NodeDeps = { llm: createLLM(cfg), sitesByCategory: {}, rng: () => 0 };

  // 重建 state：手动重试时若无 --fresh 则带上上次违规作为反馈（generateNode 会读 lastViolations）
  const state = {
    ...raw,
    lastViolations: fresh ? [] : (raw.lastViolations ?? []),
    draft: mode === "validate" ? raw.draft : undefined, // 重新生成前清掉旧 draft
  } as typeof ArticleGenState.State;

  replayLog(`重放 thread=${threadId} mode=${mode} fresh=${fresh ? "yes" : "no"} path=A (category=${state.category})`);

  if (mode === "generate" || mode === "both") {
    const gen = await generateNode(state, deps, { path: "A" });
    replayLog(
      `generateA -> ${gen.draft ? `生成成功 ${gen.draft!.paragraphs.length} 段 (${gen.draft!.titleEn.slice(0, 50)})` : `未生成: ${JSON.stringify(gen)}`}`,
    );
    if (!gen.draft) return;
    state.draft = gen.draft;
  }

  if (mode === "validate" || mode === "both") {
    const verdict = await validateNode(state, deps, { path: "A" });
    const v = verdict.lastViolations ?? [];
    if (v.length === 0) {
      replayLog(`validateA -> 通过`);
    } else {
      replayLog(`validateA -> 违规 ${v.length} 条`);
      v.forEach((x, i) => replayLog(`  [${i + 1}] [${x.ruleId}] ${x.message}`));
    }
    if (verdict.outcome) replayLog(`终态: ${verdict.outcome}${verdict.reason ? ` (${verdict.reason})` : ""}`);
  }
}

main().catch((err) => {
  console.error("重放失败:", err);
  process.exit(1);
});
