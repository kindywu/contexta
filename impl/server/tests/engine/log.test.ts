// tests/engine/log.test.ts
// 日志模块：CLI 默认行为（run-<时间戳>.log）保持不变；daily 前缀按当天日期命名文件；
// cleanupOldLogs 按文件名日期做 7 天保留轮转（早于今天-6 天删除，含今天 7 天）。
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cleanupOldLogs, initLog, log, logFilePath } from "../../src/engine/graph/log";
import { localDate } from "../../src/engine/utils/time";

const TZ = "Asia/Shanghai";

/** 相对今天 offset 天的日期（日历减法，避免 DST/毫秒误差）。 */
function dateAgo(days: number): string {
  const [y, m, d] = localDate(TZ).split("-").map(Number);
  return localDate(TZ, new Date(y, m - 1, d - days));
}

function tmpDir(): string {
  return mkdtempSync(join(tmpdir(), "log-test-"));
}

describe("initLog / log", () => {
  test("默认（CLI）→ run-<时间戳>.log，与旧行为一致", () => {
    const dir = tmpDir();
    const p1 = initLog(dir, TZ);
    expect((p1.split("/").pop() ?? "").match(/^run-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}\.log$/)).not.toBeNull();
    log("cli-line-1");
    const runFiles = readdirSync(dir).filter((f) => f.startsWith("run-"));
    expect(runFiles).toHaveLength(1);
    expect(readFileSync(join(dir, runFiles[0]!), "utf8")).toContain("cli-line-1");
    expect(logFilePath()).toBe(join(dir, runFiles[0]!));
    rmSync(dir, { recursive: true, force: true });
  });

  test("daily 前缀 → 写入 daily-<今天>.log，多次写同一文件", () => {
    const dir = tmpDir();
    const p = initLog(dir, TZ, { prefix: "daily", echo: false });
    expect(p).toBe(join(dir, `daily-${localDate(TZ)}.log`));
    log("daily-line-1");
    log("daily-line-2");
    expect(logFilePath()).toBe(join(dir, `daily-${localDate(TZ)}.log`));
    const content = readFileSync(join(dir, `daily-${localDate(TZ)}.log`), "utf8");
    expect(content).toContain("daily-line-1");
    expect(content).toContain("daily-line-2");
    rmSync(dir, { recursive: true, force: true });
  });
});

describe("cleanupOldLogs", () => {
  test("删除 7 天前的 *.log（含更早），保留 7 天内与无日期文件", () => {
    const dir = tmpDir();
    writeFileSync(join(dir, `daily-${dateAgo(8)}.log`), "old");
    writeFileSync(join(dir, `server-${dateAgo(7)}.log`), "old");
    writeFileSync(join(dir, `daily-${dateAgo(6)}.log`), "keep");
    writeFileSync(join(dir, `daily-${dateAgo(0)}.log`), "today");
    writeFileSync(join(dir, "nodate.log"), "keep");

    const removed = cleanupOldLogs(dir, 7, TZ);

    expect(removed).toBe(2); // 8 天前 + 7 天前被删，6 天前开始保留
    expect(readdirSync(dir).sort()).toEqual(
      [`daily-${dateAgo(0)}.log`, `daily-${dateAgo(6)}.log`, "nodate.log"].sort(),
    );
    rmSync(dir, { recursive: true, force: true });
  });

  test("目录不存在 → 返回 0 不抛", () => {
    expect(cleanupOldLogs(join(tmpdir(), "no-such-log-dir"), 7, TZ)).toBe(0);
  });
});
