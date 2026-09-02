// 移植 Rust services/llm_service.rs 的 word_lookup（查词网关）。
// 关键语义（与 Rust 逐条对齐）：
// 1. 缓存命中不调 LLM 不扣配额；缓存 JSON 反序列化失败 = 坏缓存 → 删行自愈继续走 LLM
// 2. 配额只计真实 LLM 调用（usage_log word_lookup 行数，今日零点起）；users.quota_word_daily 覆盖全局默认
// 3. 记账在解析之前——LLM 调用成功即记账（解析失败也计配额）；记账失败仅降级告警
// 4. 写缓存仅当 parsed.spelling.toLowerCase() === key；超容量删最旧 1 条；写失败降级告警
import type { Database } from "bun:sqlite";
import type { ServerConfig } from "../config";
import { badRequest, pipelineBlocking, quotaExceeded } from "../response";
import { parseWordLookup, type WordLookup } from "../llm/lookup_parser";
import { lookupSystemPrompt, lookupUserPrompt } from "../llm/prompt";
import { callWithRetry, type ChatFn } from "../llm/retry";
import { todayStartMillis } from "../time";

const DAY_MS = 86_400_000;

export async function wordLookup(
  db: Database,
  cfg: ServerConfig,
  chat: ChatFn,
  phone: string,
  word: string,
  timeZone: string = cfg.timeZone,
): Promise<WordLookup> {
  const key = word.trim().toLowerCase();
  if (key === "") {
    throw badRequest("empty word", "BAD_PARAM");
  }
  // 缓存（命中但反序列化失败 = 坏缓存：删行自愈，继续走 LLM）
  const cached = db
    .query("SELECT result_json FROM word_lookup_cache WHERE word = ? AND created_at >= ?")
    .get(key, Date.now() - cfg.cacheTtlDays * DAY_MS) as { result_json: string } | undefined;
  if (cached) {
    try {
      return JSON.parse(cached.result_json) as WordLookup;
    } catch {
      console.warn(`corrupt word_lookup_cache row for ${JSON.stringify(key)}, deleting and re-generating`);
      try {
        db.query("DELETE FROM word_lookup_cache WHERE word = ?").run(key);
      } catch (e) {
        console.warn(`failed to delete corrupt cache row ${JSON.stringify(key)}:`, e);
      }
    }
  }
  // 配额
  const quota = userQuota(db, cfg, phone);
  const start = todayStartMillis(timeZone);
  const used = (
    db
      .query("SELECT COUNT(*) as c FROM usage_log WHERE phone = ? AND endpoint = 'word_lookup' AND created_at >= ?")
      .get(phone, start) as { c: number }
  ).c;
  if (used >= quota) {
    throw quotaExceeded("daily word lookup quota exceeded");
  }
  // LLM（system/user 内嵌默认提示词；{{word}} 替换为原始入参词，对齐 Rust）
  const system = lookupSystemPrompt;
  const user = lookupUserPrompt(word);
  const started = Date.now();
  const resp = await callWithRetry(() => chat(system, user), cfg.llmTimeoutSecs * 1000);
  const latency = Date.now() - started;
  // 用量记账：LLM 调用成功（真实花钱）即记账，无论解析/写缓存结果如何——
  // 解析失败也计配额，堵住"易触发解析失败的词无限烧钱"的绕过口。
  // 记账失败仅降级告警（磁盘满/写繁忙时不得把成功查词变 500）。
  try {
    recordUsage(db, phone, "word_lookup", resp.promptTokens, resp.completionTokens, latency);
  } catch (e) {
    console.warn(`record_usage failed for word_lookup ${JSON.stringify(key)}:`, e);
  }
  const parsed = parseWordLookup(resp.content);
  if (!parsed) throw pipelineBlocking("unparseable LLM response");
  // 写缓存：spelling 与请求词不一致（LLM 输出变体/屈折）不入缓存，
  // 否则请求词 key 会向全用户共享缓存写入错误词条；写失败仅降级告警（结果仍返回）。
  if (parsed.spelling.toLowerCase() === key) {
    try {
      writeCache(db, cfg, key, parsed);
    } catch (e) {
      console.warn(`word_lookup cache write failed for ${JSON.stringify(key)}:`, e);
    }
  }
  return parsed;
}

/** users.quota_word_daily 可空（SQL NULL）：回退全局默认配额。 */
function userQuota(db: Database, cfg: ServerConfig, phone: string): number {
  const row = db
    .query("SELECT quota_word_daily FROM users WHERE phone = ?")
    .get(phone) as { quota_word_daily: number | null } | undefined;
  return row?.quota_word_daily ?? cfg.wordQuotaDaily;
}

function recordUsage(
  db: Database,
  phone: string,
  endpoint: string,
  promptTokens: number,
  completionTokens: number,
  latencyMs: number,
): void {
  db.query(
    "INSERT INTO usage_log (phone, endpoint, prompt_tokens, completion_tokens, latency_ms, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).run(phone, endpoint, promptTokens, completionTokens, latencyMs, Date.now());
}

/** 写缓存（容量上限：超则删最旧一条，INSERT OR REPLACE 覆盖同 key）。 */
function writeCache(db: Database, cfg: ServerConfig, key: string, parsed: WordLookup): void {
  const count = (db.query("SELECT COUNT(*) as c FROM word_lookup_cache").get() as { c: number }).c;
  if (count >= cfg.cacheMaxRows) {
    db.query(
      "DELETE FROM word_lookup_cache WHERE word = (SELECT word FROM word_lookup_cache ORDER BY created_at ASC LIMIT 1)",
    ).run();
  }
  db.query("INSERT OR REPLACE INTO word_lookup_cache (word, result_json, created_at) VALUES (?, ?, ?)").run(
    key,
    JSON.stringify(parsed),
    Date.now(),
  );
}

export const llmService = { wordLookup };
