import { Hono } from "hono";
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { attachErrorHandler, ok } from "../response";
import { resolveAuthUser } from "../auth";
import { llmService } from "../services/llm_service";
import { driverChat, type ChatFn, type LlmDriverOptions } from "../llm/retry";

/** 缺省驱动：driverChat ⨯ cfg（LLM 端点字段来自 ServerConfig）。 */
function defaultChat(cfg: ServerConfig): ChatFn {
  const opts: LlmDriverOptions = {
    baseUrl: cfg.llmBaseUrl,
    apiKey: cfg.llmApiKey,
    model: cfg.llmModel,
    proxyUrl: cfg.proxyUrl,
    timeoutMs: cfg.llmTimeoutSecs * 1000,
  };
  return (system, user) => driverChat(opts, system, user);
}

export function llmRouter(db: Database, cfg: ServerConfig, chat?: ChatFn): Hono {
  const app = new Hono();
  attachErrorHandler(app);

  app.post("/api/llm/word-lookup", async (c) => {
    const user = resolveAuthUser(db, cfg, c.req.header("authorization"));
    const body = await c.req.json<{ word?: string }>();
    const result = await llmService.wordLookup(
      db,
      cfg,
      chat ?? defaultChat(cfg),
      user.phone,
      body.word ?? "",
      cfg.timeZone,
    );
    return c.json(ok(result));
  });

  return app;
}
