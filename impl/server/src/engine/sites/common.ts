/**
 * 站点抓取的公共部分：浏览器视图（Bun.WebView）、锚点快照采集、
 * 正文 HTML 提取与清洗、列表清洗小工具。
 * 具体站点的抽取规则见 chinadaily.ts / tencent.ts。
 *
 * 调试追踪（2026-09-16 事故教训）：Linux 上 Bun.WebView 经 CDP 驱动
 * chrome-headless-shell，Chrome 侧一旦异常（实测 compositor CHECK 失败 →
 * 内核 trap int3），挂起的 evaluate 永不 settle——而 pollUntil 的 30s 超时
 * 只作用于"两次轮询之间"，救不了卡在 await 里的一次调用；于是整批静默卡死
 * （槽位无任何 [sites] 日志，批次永不收口，结束卡永不发出）。
 * 因此本文件对视图全生命周期打点：创建/导航/轮询/清洗/关闭各记一行，
 * 并给可能永久挂起的调用挂"阻塞心跳"（只记日志，不改语义）；
 * 活动视图数与存活 Chrome 进程数一并入日志，供事后按 [wv#N] 归属定位。
 */

import { readFileSync, readdirSync } from "node:fs";
import { performance } from "node:perf_hooks";
import { log } from "../graph/log";
import { fmtMs } from "../utils/format";
import { pollUntil } from "../utils/wait";

export interface ArticleLink {
  title: string;
  url: string;
}

/** 文章正文抓取结果：标题 + 原文 URL + 清洗后的正文 HTML。 */
export interface ArticleHtml {
  title: string;
  url: string;
  html: string;
}

/**
 * 站点访问的统一接口：第一批（列表）+ 第二批（正文）。
 * 每个站点一份实现（见 chinadaily.ts / tencent.ts），外界不感知具体解析差异。
 */
export interface SiteFetcher {
  readonly name: string; // 适配器自带名称；配置条目 name 必须与之一致（defineSites 守卫）
  /** 首页文章列表（标题 + URL）；homeUrl 由站点配置（sites.config.ts）传入 */
  fetchLinks(homeUrl: string): Promise<ArticleLink[]>;
  /** 抓取指定文章的正文 HTML（已去除其他链接和广告）。 */
  fetchArticle(link: ArticleLink): Promise<ArticleHtml>;
}

/** 浏览器内取到的锚点快照：文本、href、class 及直接子元素文本。 */
export interface AnchorSnap {
  href: string;
  text: string;
  cls: string;
  childTexts: string[];
}

/** 视图追踪：单调编号（并发抓取时用 [wv#N] 归属日志）+ 当前活动视图数（= 共享 Chrome 里的标签页数）。 */
let viewSeq = 0;
let activeViews = 0;

/**
 * 浏览器并发闸（`BROWSER_CONCURRENCY`）：限制同一时刻打开的视图数。
 * 为什么需要：Chrome 每进程一个、被所有视图共享，每开一个视图就多一个 renderer
 * 与 1440×2000 的合成缓冲（吃 /dev/shm）；不设闸时并发上限实际由 `SLOT_CONCURRENCY`
 * 决定（5 槽同时抓取 = 5 个视图），是 2026-09-16 挂死事故的相关因素之一。
 * 缺省 2（与 config 的 BROWSER_CONCURRENCY 缺省一致），启动时经
 * `setBrowserConcurrency(cfg.browserConcurrency)` 覆盖。
 */
let browserConcurrency = 2;
let browserBusy = 0;
const browserWaiters: (() => void)[] = [];

/** 设置浏览器并发上限（非有限值或 < 1 时忽略，保持原值）。 */
export function setBrowserConcurrency(n: number): void {
  if (!Number.isFinite(n) || n < 1) return;
  browserConcurrency = Math.floor(n);
}

/** 取一个浏览器槽位（满则排队等待）；必须与 releaseBrowserSlot 成对调用。 */
async function acquireBrowserSlot(): Promise<void> {
  while (browserBusy >= browserConcurrency) {
    await new Promise<void>((resolve) => browserWaiters.push(resolve));
  }
  browserBusy++;
}

/** 归还浏览器槽位并唤醒一个排队者。 */
function releaseBrowserSlot(): void {
  browserBusy--;
  browserWaiters.shift()?.();
}

/**
 * 调用超时（毫秒）——与"记日志"不同，超时是**动作**：到点即判本次调用失败，并强杀
 * 浏览器子进程让挂起的 promise 立刻 reject（见 guardCall）。取值 = 正常耗时（毫秒级）
 * + 调用自身的内部预算：导航类无内部预算给 15s；pollUntil 与正文清洗脚本各自内部
 * 有 30s 预算，外层给 45s——越过 45s 即真卡死，而非"慢"。
 */
const NAVIGATE_TIMEOUT_MS = 15_000;
const EVALUATE_TIMEOUT_MS = 30_000;
const POLL_TIMEOUT_MS = 45_000;
const CLEAN_TIMEOUT_MS = 45_000;

/**
 * 存活 chrome-headless-shell 浏览器进程数（仅 Linux；读不到返回 -1）。
 * 注意 Chrome **每进程一个**（首个 `new Bun.WebView()` 启动，后续视图经
 * `Target.createTarget` 复用同一实例），所以服务进程内正常值恒为 0 或 1：
 * >1 说明还有别的浏览器进程（如残留的调试容器），0 说明子进程已被
 * `closeAll` 或进程退出回收。视图数看 activeViews，两者别混为一谈。
 */
function countChromeBrowsers(): number {
  if (process.platform !== "linux") return -1;
  try {
    let n = 0;
    for (const pid of readdirSync("/proc")) {
      const c = pid.charCodeAt(0);
      if (c < 48 || c > 57) continue; // 跳过非数字目录项
      try {
        const cmd = readFileSync(`/proc/${pid}/cmdline`, "utf8");
        // 只数浏览器主进程（带 --remote-debugging-pipe），不数 zygote/gpu/renderer 子进程
        if (cmd.includes("chrome-headless-shell") && cmd.includes("--remote-debugging-pipe")) n++;
      } catch {
        // 进程刚退出 / 无权限读 cmdline：跳过
      }
    }
    return n;
  } catch {
    return -1;
  }
}

/** Chrome 进程数渲染片段（非 Linux/读不到则省略，不制造噪音）。 */
function chromeCountText(): string {
  const n = countChromeBrowsers();
  return n < 0 ? "" : `，chrome 进程 ${n}`;
}

function errText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/**
 * 受控调用：记完成/失败与耗时，并给调用加**硬超时**。到点做两件事：
 * 1) `Bun.WebView.closeAll()` 强杀浏览器子进程——Bun 文档保证"所有视图上挂起的
 *    promise 在下一个事件循环 tick reject"，这是唯一能解开已卡死 CDP 调用的手段
 *    （换新视图没用：Chrome **每进程一个**，会复用同一个卡住的实例）；
 * 2) reject，让调用方按普通失败处理（换篇/槽位 error），批次得以照常收口。
 * 代价：closeAll 会打断同进程内其他并发抓取，它们各自记为失败——远好于整批静默卡死。
 */
function guardCall<T>(
  p: Promise<T>,
  opts: { id: number; label: string; timeoutMs: number },
): Promise<T> {
  // 超时后原 promise 仍可能 settle（或被 closeAll 拒绝）：先挂空 catch，避免未处理拒绝
  p.catch(() => {});
  let timer: ReturnType<typeof setTimeout> | undefined;
  const guard = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      log(
        `[sites] [wv#${opts.id}] ${opts.label} 超时 ${fmtMs(opts.timeoutMs)} 未返回 -> 判定卡死，强杀浏览器子进程（同进程并发抓取会一并失败）`,
      );
      try {
        Bun.WebView.closeAll();
      } catch (e) {
        log(`[sites] [wv#${opts.id}] ${opts.label} closeAll 异常: ${errText(e)}`);
      }
      reject(new Error(`${opts.label} 超时 ${opts.timeoutMs}ms 未返回（Chrome/CDP 无响应，已强杀浏览器子进程）`));
    }, opts.timeoutMs);
  });
  const t0 = performance.now();
  return Promise.race([p, guard]).then(
    (v) => {
      if (timer) clearTimeout(timer);
      log(`[sites] [wv#${opts.id}] ${opts.label} 完成 耗时 ${fmtMs(performance.now() - t0)}`);
      return v;
    },
    (e: unknown) => {
      if (timer) clearTimeout(timer);
      log(`[sites] [wv#${opts.id}] ${opts.label} 失败 耗时 ${fmtMs(performance.now() - t0)}: ${errText(e)}`);
      throw e;
    },
  );
}

/** 软导航与空白导航：无内部预算，15s 上限。 */
const navCall = <T>(p: Promise<T>, id: number, label: string): Promise<T> =>
  guardCall(p, { id, label, timeoutMs: NAVIGATE_TIMEOUT_MS });

/** 一次性 evaluate（取快照）：本应毫秒级返回，30s 上限。 */
const evalCall = <T>(p: Promise<T>, id: number, label: string): Promise<T> =>
  guardCall(p, { id, label, timeoutMs: EVALUATE_TIMEOUT_MS });

/** pollUntil：自身预算 30s，45s 上限即代表真卡死。 */
const pollCall = <T>(p: Promise<T>, id: number, label: string): Promise<T> =>
  guardCall(p, { id, label, timeoutMs: POLL_TIMEOUT_MS });

/** 正文清洗脚本：自身预算 30s，45s 上限即代表真卡死。 */
const cleanCall = <T>(p: Promise<T>, id: number, label: string): Promise<T> =>
  guardCall(p, { id, label, timeoutMs: CLEAN_TIMEOUT_MS });

/**
 * 创建受追踪的视图：先取浏览器并发槽位（满则排队），再记一行、再创建——
 * 卡在排队或创建里时日志都能明确指向它。创建失败必须自行归还槽位：调用方是
 * `const { view } = await openView()` 后再 `try/finally closeView`，拿不到 view
 * 就不会走 closeView，槽位只能在这里还。
 */
async function openView(label: string): Promise<{ view: Bun.WebView; id: number }> {
  const id = ++viewSeq;
  await acquireBrowserSlot();
  try {
    log(`[sites] [wv#${id}] ${label} 创建视图（活动视图 ${activeViews}，排队 ${browserWaiters.length}${chromeCountText()}）`);
    const t0 = performance.now();
    const view = new Bun.WebView({
      width: 1440,
      height: 2000,
      ...webViewOptions(),
    });
    activeViews++;
    log(
      `[sites] [wv#${id}] ${label} 视图就绪 耗时 ${fmtMs(performance.now() - t0)}（活动视图 ${activeViews}）`,
    );
    return { view, id };
  } catch (e) {
    releaseBrowserSlot();
    throw e;
  }
}

/**
 * 关闭视图：归还浏览器并发槽位 + 记关闭耗时（close() 是同步的——若"视图已关闭"
 * 这行不出现，即为卡在 close 里）。归还放 finally：关闭异常也必须释放闸门。
 */
function closeView(view: Bun.WebView, id: number, label: string): void {
  const t0 = performance.now();
  try {
    view.close();
    activeViews--;
    log(
      `[sites] [wv#${id}] ${label} 视图已关闭 耗时 ${fmtMs(performance.now() - t0)}（活动视图 ${activeViews}${chromeCountText()}）`,
    );
  } catch (e) {
    activeViews--;
    log(
      `[sites] [wv#${id}] ${label} 视图关闭异常: ${errText(e)}（活动视图 ${activeViews}${chromeCountText()}）`,
    );
  } finally {
    releaseBrowserSlot();
  }
}

/** 在页面里执行选择器取快照的脚本（evaluate 只收表达式，包成 IIFE）。 */
const snapshotScript = (selector: string) => `(() => {
  const anchors = [...document.querySelectorAll(${JSON.stringify(selector)})];
  return anchors.map((a) => ({
    href: a.href,
    text: (a.textContent ?? "").replace(/\\s+/g, " ").trim(),
    cls: a.className,
    childTexts: [...a.children].map((c) =>
      (c.textContent ?? "").replace(/\\s+/g, " ").trim(),
    ),
  }));
})()`;

/**
 * 软导航：给页面赋值 location.href，立即返回，不等页面完整加载。
 * Bun.WebView.navigate() 会等全部子资源（图片、广告、统计脚本）加载完才 resolve，
 * 慢站点（实测中国日报首页挂起 130s+）因此极为耗时；而 DOM 实际 1~2s 就绪，
 * 所以我们改为自行跳转 + 轮询 DOM。
 */
async function navigateLite(
  view: Bun.WebView,
  id: number,
  label: string,
  pageUrl: string,
): Promise<void> {
  if (!view.url) {
    // 首次使用先建立稳定的空白上下文
    await navCall(view.navigate("about:blank"), id, `${label} 空白导航`);
  }
  await navCall(
    view.evaluate(`location.href = ${JSON.stringify(pageUrl)}`),
    id,
    `${label} 软导航`,
  );
}

/**
 * WebView 构造选项（跨平台）。
 * Linux：Bun.WebView 走 Chrome 后端（镜像内 chrome-headless-shell，镜像层
 * BUN_CHROME_PATH 指向）；root 容器内 Chrome 必须以 --no-sandbox 启动——
 * 容器内无砂箱可复用，而 Bun spawn 的默认参数不带该项（遗漏即 Chrome
 * 启动即退，报 "Chrome process closed the pipe"，见 docs/config-and-deploy.md §6）。
 * macOS：默认 WebKit 后端，无需 backend。
 */
function webViewOptions() {
  return process.platform === "linux"
    ? { backend: { type: "chrome" as const, argv: ["--no-sandbox"] } }
    : {};
}

/**
 * 打开页面，等动态新闻列表填充后，返回匹配选择器的锚点快照。
 * 页面加载完成后视图即关闭，快照数组与浏览器生命周期无关。
 */
export async function fetchAnchorSnapshots(
  pageUrl: string,
  selector: string,
): Promise<AnchorSnap[]> {
  const label = `列表 ${pageUrl}`;
  const { view, id } = await openView(label);
  try {
    await navigateLite(view, id, label, pageUrl);
    const tWait = performance.now();
    // 列表是 JS 懒加载的（实测腾讯 6s 左右注入），必须等选择器真正命中——
    // 不能用"页面里 a 数量多"之类的替代条件，页脚链接会提前满足导致空列表。
    const ok = await pollCall(
      pollUntil(() => view.evaluate<boolean>(`!!document.querySelector(${JSON.stringify(selector)})`)),
      id,
      `${label} 轮询列表填充`,
    );
    if (!ok) {
      log(`[sites] [wv#${id}] ${label} 等待超时(30s)，按当前 DOM 继续`);
    }
    const tExtract = performance.now();
    const snaps = await evalCall(
      view.evaluate<AnchorSnap[]>(snapshotScript(selector)),
      id,
      `${label} 提取锚点`,
    );
    log(
      `[sites] [wv#${id}] ${label} | 等待填充 ${fmtMs(tExtract - tWait)} | 提取 ${fmtMs(performance.now() - tExtract)} | ${snaps.length} 条`,
    );
    return snaps;
  } finally {
    closeView(view, id, label);
  }
}

/**
 * 正文清洗脚本：在页面内对正文容器克隆加清洗，返回 { found, html }。
 * - 超链接解包（保留文字，去掉链接本身）
 * - 删除 script/style/iframe/form/视频等非正文节点
 * - 删除 class/id 带广告、推荐、分享等特征的节点
 *
 * @param containerSelector 主容器选择器
 * @param fallback 主容器未命中时的兜底表达式（页面内 IIFE，返回要清洗的节点或 null）。
 *   用于站点的次级模板（如腾讯 UTR 链接的聚合页正文不在主容器里）。
 */
export const cleanArticleScript = (
  containerSelector: string,
  fallback?: string,
) => `(() => {
  return (async () => {
    const clean = (root) => {
      for (const a of root.querySelectorAll("a")) {
        const parent = a.parentNode;
        if (!parent) continue;
        while (a.firstChild) parent.insertBefore(a.firstChild, a);
        parent.removeChild(a);
      }
      for (const n of root.querySelectorAll("script, style, iframe, form, noscript, aside, footer, nav, button, video, embed, object")) {
        n.remove();
      }
      const noiseAttr = "[class*='ad'],[class*='banner'],[class*='recommend'],[class*='related'],[class*='share'],[class*='footer'],[class*='nav'],[class*='guess'],[class*='hotlink'],[id*='ad'],[id*='banner'],[id*='recommend'],[id*='related'],[id*='share']";
      for (const n of root.querySelectorAll(noiseAttr)) n.remove();
      // 编辑器的内联排版样式（腾讯富文本大量带《style》）是纯噪声，统一去掉
      for (const n of root.querySelectorAll("[style]")) n.removeAttribute("style");
      return root.innerHTML;
    };
    const sel = ${JSON.stringify(containerSelector)};
    // 先立即尝试主容器与兜底：文章页导航完成即渲染，轮询只是防懒加载的兜底
    let el = document.querySelector(sel);
    if (el) return { found: true, html: clean(el.cloneNode(true)) };
    const fbEl = ${fallback ? `((${fallback})())` : "null"};
    if (fbEl) return { found: true, html: clean(fbEl) };
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      el = document.querySelector(sel);
      if (el) return { found: true, html: clean(el.cloneNode(true)) };
      await new Promise((r) => setTimeout(r, 300));
    }
    return { found: false, html: "" };
  })();
})()`;

/**
 * 打开文章页，等正文容器出现后进行清洗，返回正文 HTML 字符串。
 * @param pageUrl 文章 URL
 * @param containerSelector 正文容器选择器（站点各自维护，见 chinadaily.ts / tencent.ts）
 * @param fallback 主容器未命中时的兜底提取表达式（页面内 IIFE，返回节点或 null）。
 *   如腾讯 UTR 链接（专题/热点聚合文）没有主容器，正文段落是普通 <p>。
 */
export async function fetchArticleHTML(
  pageUrl: string,
  containerSelector: string,
  fallback?: string,
): Promise<string> {
  const label = `正文 ${pageUrl}`;
  const { view, id } = await openView(label);
  try {
    await navigateLite(view, id, label, pageUrl);
    const tWait = performance.now();
    const ok = await pollCall(
      pollUntil(() =>
        view.evaluate<boolean>(
          `(() => {
          const sel = ${JSON.stringify(containerSelector)};
          if (document.querySelector(sel)) return true;
          return ${fallback ? `!!((${fallback})())` : "false"};
        })()`,
        ),
      ),
      id,
      `${label} 轮询正文容器`,
    );
    if (!ok) {
      log(
        `[sites] [wv#${id}] 正文容器 ${containerSelector} (${pageUrl}) 等待超时(30s)，按当前 DOM 继续`,
      );
    }
    const tExtract = performance.now();
    const res = await cleanCall(
      view.evaluate<{ found: boolean; html: string }>(
        cleanArticleScript(containerSelector, fallback),
      ),
      id,
      `${label} 清洗正文`,
    );
    if (!res.found) {
      throw new Error(
        `文章正文容器 ${containerSelector} 在页面中未找到（兜底也未命中）: ${pageUrl}`,
      );
    }
    log(
      `[sites] [wv#${id}] 正文 ${pageUrl} | 等待容器 ${fmtMs(tExtract - tWait)} | 清洗 ${fmtMs(performance.now() - tExtract)} | ${res.html.length} 字节`,
    );
    return res.html;
  } finally {
    closeView(view, id, label);
  }
}

/** 从文章列表中随机取一篇；空列表直接抛错。 */
export function pickRandom(links: ArticleLink[]): ArticleLink {
  if (links.length === 0) {
    throw new Error("文章列表为空，无法随机选择");
  }
  return links[Math.floor(Math.random() * links.length)]!;
}

export function cleanTitle(t: string): string {
  return t.replace(/\s+/g, " ").trim();
}

export function stripQuery(href: string): string {
  return href.split("?")[0]!;
}

/** 同 URL 只保留首次出现（首页上同一文章往往出现在多个栏目展位）。 */
export function dedupe(links: ArticleLink[]): ArticleLink[] {
  const seen = new Set<string>();
  const out: ArticleLink[] = [];
  for (const l of links) {
    if (seen.has(l.url)) continue;
    seen.add(l.url);
    out.push(l);
  }
  return out;
}
