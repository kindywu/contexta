/**
 * tool 脚本共用的 Bun.WebView 抓取骨架：硬超时守卫、跨平台视图选项、
 * 页面内串行批量下载 + 外层落盘。
 *
 * 为什么在**页面上下文里** fetch 而不是外层 fetch/curl：目标站点对非浏览器
 * 客户端会限流或拒（返回拦截页 / 429），在页面里 fetch 既带上浏览器自身的
 * UA / Cookie / TLS 指纹，又不触发 CORS。项目里抓站一贯如此
 * （见 src/engine/sites/common.ts）。
 */

import { writeFileSync } from "node:fs";
import { join } from "node:path";

/** 一次页面内批量取回的结果。 */
export interface FetchResult {
  url: string;
  ok: boolean;
  b64?: string;
  bytes?: number;
  err?: string;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * 受控调用：给可能永久挂起的 WebView 调用加硬超时。
 * 到点强杀浏览器子进程（Bun 保证挂起的 promise 在下一 tick reject）——这是解开
 * 已卡死 CDP 调用的唯一手段，换新视图没用（Chrome 每进程一个，会复用同一实例）。
 * 语义与 src/engine/sites/common.ts 的 guardCall 一致，此处按需精简。
 */
export function guard<T>(p: Promise<T>, label: string, timeoutMs: number): Promise<T> {
  p.catch(() => {});
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      try {
        Bun.WebView.closeAll();
      } catch {
        /* 关不掉也要照常失败 */
      }
      reject(new Error(`${label} 超时 ${timeoutMs}ms 未返回（已强杀浏览器子进程）`));
    }, timeoutMs);
  });
  return Promise.race([p, timeout]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

export const NAV_TIMEOUT_MS = 15_000;

/** 跨平台视图选项：Linux 走 chrome-headless-shell，root 容器内必须 --no-sandbox。 */
export function viewOptions() {
  return process.platform === "linux"
    ? { backend: { type: "chrome" as const, argv: ["--no-sandbox"] } }
    : {};
}

/**
 * 软导航到目标页并轮询到 `readyExpr` 为真。
 *
 * 为什么不直接 navigate()：它要等全部子资源（广告/统计脚本）加载完，慢站点实测
 * 挂起过百秒；DOM 实际一两秒就绪，所以自行跳转 + 轮询。
 */
export async function gotoAndWait(
  view: Bun.WebView,
  url: string,
  readyExpr: string,
  opts: { tries?: number; intervalMs?: number } = {},
): Promise<boolean> {
  const tries = opts.tries ?? 60;
  const intervalMs = opts.intervalMs ?? 500;
  await guard(view.navigate("about:blank"), "空白导航", NAV_TIMEOUT_MS);
  await guard(view.evaluate(`location.href = ${JSON.stringify(url)}`), "软导航", NAV_TIMEOUT_MS);
  for (let i = 0; i < tries; i++) {
    if (await guard(view.evaluate<boolean>(readyExpr), "轮询页面就绪", 10_000)) return true;
    await sleep(intervalMs);
  }
  return false;
}

/**
 * 页面内批量下载并转 base64。
 *
 * **串行 + 退避重试**，不是并发：实测并发抓（Promise.all 8 个）会在百来个请求后
 * 触发源站限流 429——批量越大越快撞。单个录音约 25KB，几十上百个文件的代价可以接受。
 * 429 优先读 Retry-After，取不到就指数退避（1s/2s/4s/8s，上限 30s）。
 * credentials: include —— 带上页面自身的 Cookie，与真实播放器同一条请求路径。
 */
function fetchScript(urls: string[], delayMs: number): string {
  return `(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const one = async (url) => {
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        const res = await fetch(url, { credentials: "include" });
        if (res.status === 429 || res.status >= 500) {
          if (attempt === 4) return { url, ok: false, err: "HTTP " + res.status + "（重试耗尽）" };
          const ra = Number(res.headers.get("retry-after"));
          const wait = Number.isFinite(ra) && ra > 0
            ? Math.min(30_000, ra * 1000)
            : Math.min(30_000, 1000 * 2 ** attempt);
          await sleep(wait);
          continue;
        }
        if (!res.ok) return { url, ok: false, err: "HTTP " + res.status };
        const buf = new Uint8Array(await res.arrayBuffer());
        let s = "";
        const CH = 0x8000;
        for (let i = 0; i < buf.length; i += CH) {
          s += String.fromCharCode.apply(null, buf.subarray(i, i + CH));
        }
        return { url, ok: true, b64: btoa(s), bytes: buf.length };
      } catch (e) {
        if (attempt === 4) return { url, ok: false, err: String(e) };
        await sleep(Math.min(30_000, 1000 * 2 ** attempt));
      }
    }
    return { url, ok: false, err: "重试耗尽" };
  };
  const out = [];
  for (const u of ${JSON.stringify(urls)}) {
    out.push(await one(u));
    await sleep(${delayMs});
  }
  return out;
})()`;
}

/**
 * 落盘前校验：合法 mp3 要么带 ID3 头，要么以 MPEG 同步字 0xFF 开头。
 * 拦下「HTTP 200 但内容其实是 HTML 拦截页」。
 */
export function looksAudio(buf: Buffer): boolean {
  return buf.length >= 512 && (buf.subarray(0, 3).toString("latin1") === "ID3" || buf[0] === 0xff);
}

/** 一个待抓文件：源地址 + 落盘文件名（由调用方决定命名规则）。 */
export interface DownloadJob {
  url: string;
  file: string;
}

/**
 * 按批从页面上下文取回所有文件并落盘。返回结果与 `jobs` **同序等长**，
 * 便于调用方按索引回填（不靠 URL 反查——同名 URL 或多文件同名都不影响）。
 * 批超时/异常不致命：整批记为失败，由调用方报告（失败重跑即可补缺口）。
 */
export async function downloadAll(
  view: Bun.WebView,
  jobs: DownloadJob[],
  opts: { out: string; batch: number; delay: number },
): Promise<FetchResult[]> {
  const all: FetchResult[] = [];
  for (let i = 0; i < jobs.length; i += opts.batch) {
    const chunk = jobs.slice(i, i + opts.batch);
    const results = await guard(
      view.evaluate<FetchResult[]>(fetchScript(chunk.map((j) => j.url), opts.delay)),
      `下载第 ${i / opts.batch + 1} 批`,
      // 一批串行 + 退避重试：单个最坏 5 次尝试 × 30s 退避，预算给足；
      // 真卡死时由 guard 强杀浏览器而非干等。
      180_000,
    ).catch((e: unknown) => {
      console.log(`  批失败，整批跳过: ${e instanceof Error ? e.message : String(e)}`);
      return chunk.map<FetchResult>((j) => ({ url: j.url, ok: false, err: "批超时/异常" }));
    });

    // 页面内串行执行，返回顺序即请求顺序 → 按索引与 chunk 对齐
    for (let k = 0; k < chunk.length; k++) {
      const job = chunk[k]!;
      const r = results[k] ?? { url: job.url, ok: false, err: "结果缺失" };
      if (!r.ok) {
        console.log(`  ✗ ${job.file} — ${r.err}`);
      } else {
        const buf = Buffer.from(r.b64!, "base64");
        if (!looksAudio(buf)) {
          console.log(`  ✗ ${job.file} — 内容不是音频（${buf.length} 字节）`);
          r.ok = false;
          r.err = "内容不是音频";
        } else {
          writeFileSync(join(opts.out, job.file), buf);
        }
      }
      all.push(r);
    }
    const done = Math.min(i + opts.batch, jobs.length);
    console.log(`  ... ${done}/${jobs.length}`);
    if (done < jobs.length) await sleep(400);
  }
  return all;
}
