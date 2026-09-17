// tests/tls.test.ts
// HTTPS 自签名（固定 IP 无域名）落地验证：
// - main.ts TLS 生效路径 = 证书文件 PEM 内容直传 Bun.serve.tls（Bun 1.4.2 不认路径，
//   传路径会 ERR_OSSL_PEM_NO_START_LINE——此文件即该结论的回归防线）；
// - 起真实端口，分别以"跳过校验"与"以该证书为信任锚"两种客户端验证可连接；
// - 客户端信任锚校验通过 = Android network security config 内嵌同一证书的等价语义。
import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { appTlsFromConfig, buildApp } from "../src/main";
import { loadServerConfig } from "../src/config";
import { Database } from "bun:sqlite";
import { ensureServerSchema } from "../src/db";
import { ensureSchema } from "../src/engine/db";
import { loadConfig } from "../src/engine/config";

const TZ = "Asia/Shanghai";

/** 生成自签名测试证书（openssl 缺失则跳过用例——CI 与本地 macOS 均有）。 */
function makeSelfSignedCert(): { certPath: string; keyPath: string } {
  const dir = mkdtempSync(join(tmpdir(), "ctxa-tls-"));
  const certPath = join(dir, "server.crt");
  const keyPath = join(dir, "server.key");
  const res = Bun.spawnSync([
    "openssl", "req", "-x509", "-newkey", "ec",
    "-pkeyopt", "ec_paramgen_curve:prime256v1",
    "-keyout", keyPath, "-out", certPath,
    "-days", "1", "-nodes", "-sha256",
    "-subj", "/CN=127.0.0.1",
    "-addext", "subjectAltName=IP:127.0.0.1",
  ]);
  if (res.exitCode !== 0) throw new Error(`openssl 生成证书失败: ${res.stderr.toString()}`);
  return { certPath, keyPath };
}

describe("HTTPS（自签名）", () => {
  test("TLS 生效路径：loadAppTls 读 PEM 内容并起真实 HTTPS 端口", async () => {
    const { certPath, keyPath } = makeSelfSignedCert();
    const cfg = loadServerConfig({
      JWT_SECRET: "s".repeat(32), ADMIN_JWT_SECRET: "a".repeat(32),
      LLM_API_KEY: "k", TIMEZONE: TZ,
      TLS_CERT_PATH: certPath, TLS_KEY_PATH: keyPath,
    });
    const tls = appTlsFromConfig(cfg);
    expect(tls?.cert).toContain("BEGIN CERTIFICATE");
    expect(tls?.key).toContain("PRIVATE KEY");

    const db = new Database(":memory:");
    ensureSchema(db);
    ensureServerSchema(db);
    const engineCfg = {
      ...loadConfig({ LLM_API_KEY: "k", TIMEZONE: TZ }),
      dbPath: ":memory:",
      checkpointPath: join(tmpdir(), "tls-cp.sqlite"),
      outputDir: join(tmpdir(), "tls-out"),
    };
    const app = buildApp(db, cfg, engineCfg);
    const server = Bun.serve({ port: 0, fetch: app.fetch, tls: tls! });
    try {
      expect(server.protocol).toBe("https");
      // 跳过校验可连（模拟浏览器"继续访问"）
      const loose = await fetch(`https://127.0.0.1:${server.port}/api/health`, {
        tls: { rejectUnauthorized: false },
      });
      expect(loose.status).toBe(200);
      expect(await loose.json()).toEqual({ code: 0, data: { status: "ok" } });
      // 以内嵌该证书为信任锚可连（模拟 Android network security config 内嵌证书）
      const pinned = await fetch(`https://127.0.0.1:${server.port}/api/health`, {
        tls: { ca: await Bun.file(certPath).text() },
      });
      expect(pinned.status).toBe(200);
    } finally {
      server.stop();
    }
  }, 30_000);

  test("未配置证书 → tls 为 undefined（回退 HTTP，不静默带空配置启动）", () => {
    const cfg = loadServerConfig({
      JWT_SECRET: "s".repeat(32), ADMIN_JWT_SECRET: "a".repeat(32),
      LLM_API_KEY: "k", TIMEZONE: TZ,
    });
    expect(appTlsFromConfig(cfg)).toBeUndefined();
  });
});
