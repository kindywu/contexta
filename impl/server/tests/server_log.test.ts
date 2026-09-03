// tests/server_log.test.ts
// 服务端日志：initServerLog 后 serverLog/serverWarn/serverError 同时写
// logs 目录下 <dir>/server-<今天>.log 与 stdout（console）；未 init 时只 console。
import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { initServerLog, serverError, serverLog, serverWarn } from "../src/services/server_log";
import { localDate } from "../src/engine/utils/time";

const TZ = "Asia/Shanghai";

describe("server_log", () => {
  test("init 后：三种级别写入 server-<今天>.log（错误含堆栈信息）", () => {
    const dir = mkdtempSync(join(tmpdir(), "srvlog-"));
    initServerLog(dir, TZ);
    serverLog("启动完成");
    serverWarn("配额告警");
    serverError("内部错误", new Error("boom-cause"));
    const file = join(dir, `server-${localDate(TZ)}.log`);
    const content = readFileSync(file, "utf8");
    expect(content).toContain("启动完成");
    expect(content).toContain("配额告警");
    expect(content).toContain("内部错误");
    expect(content).toContain("boom-cause");
    rmSync(dir, { recursive: true, force: true });
  });

  test("init 切换目录后写入新目录（同一按天文件名）", () => {
    const dirA = mkdtempSync(join(tmpdir(), "srvlog-a-"));
    const dirB = mkdtempSync(join(tmpdir(), "srvlog-b-"));
    initServerLog(dirA, TZ);
    serverLog("to-a");
    initServerLog(dirB, TZ);
    serverLog("to-b");
    expect(readFileSync(join(dirA, `server-${localDate(TZ)}.log`), "utf8")).toContain("to-a");
    expect(readFileSync(join(dirB, `server-${localDate(TZ)}.log`), "utf8")).toContain("to-b");
    rmSync(dirA, { recursive: true, force: true });
    rmSync(dirB, { recursive: true, force: true });
  });
});
