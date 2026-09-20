/**
 * 音标发音抓取（英语音标网 → App assets）——**App 参考页实际使用的那一套**。
 *
 * 源站：https://yingyuyinbiao.com/英语元音/ （20 个）+ /英语辅音/ （28 个）= 48，
 * 正是 App `phonicsGroups` 用的那套 DJ 音标（国内教材体系）。
 *
 * 本站 48 个里只有 30 个的录音还在服务器上（另外 18 个是死链，详见 README）。
 * 缺的 18 个由 `--cambridge <dir>` 从 fetch-phonetics.ts 的产物里补齐——那批文件
 * 不随仓库携带，只在需要整份重建时临时抓一份。
 *
 * 为什么要 Bun.WebView：见 lib/webview.ts 顶部（浏览器上下文 fetch 带 UA/Cookie/
 * TLS 指纹且不触发 CORS）。mp3 与页面同源，页面内 fetch 无障碍。
 *
 * 用法：
 *   cd impl/server
 *   bun run tool/fetch-phonetics-yyb.ts -- [--out <dir>] [--force]
 *
 * 详见同目录 README.md。
 */

import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { downloadAll, gotoAndWait, guard, viewOptions } from "./lib/webview";

/** 两个页面：顺序即音标顺序（元音 20 + 辅音 28）。 */
const PAGES = [
  { key: "vowel", prefix: "v", label: "元音(20)", url: "https://yingyuyinbiao.com/英语元音/" },
  { key: "consonant", prefix: "c", label: "辅音(28)", url: "https://yingyuyinbiao.com/英语辅音/" },
] as const;

/** 缺省输出目录：Flutter App 的 assets（tool 在 impl/server/tool）。 */
const DEFAULT_OUT = join(import.meta.dir, "..", "..", "app", "flutter", "assets", "phonetics");

/** App 需求清单的来源文件（相对仓库根）。 */
const APP_DATA = join(
  import.meta.dir,
  "..",
  "..",
  "app",
  "flutter",
  "lib",
  "ui",
  "reference",
  "reference_data.dart",
);

/**
 * Cambridge 源目录（fetch-phonetics.ts 的产物）：用于补齐本站已删除的录音。
 *
 * **不设默认值**：Cambridge 那 176 个文件已不再随仓库携带（只有 18 个真用得上，
 * 且都已落在本工具的输出里）。整份重建时先把它抓到一个临时目录，例如：
 *   bun run tool/fetch-phonetics.ts --out /tmp/cambridge-phonetics
 *   bun run tool/fetch-phonetics-yyb.ts --cambridge /tmp/cambridge-phonetics
 */

/**
 * Cambridge 的 manifest 里每个音标有 uk/us 两套录音，缺口的音素取 **uk**——
 * 本站是 DJ（英式）体系，取英式保持同一口音。
 */
const CAMBRIDGE_REGION = "uk" as const;

/** 页面上解析出的一个音标条目。 */
interface Entry {
  symbol: string; // 页面原文，如 "i:" / "əU"
  keyword: string; // 例词，如 "see/she"
  table: string; // 表格标题行（如 "双元音"），页内分组用
  url: string; // mp3 绝对地址
}

/** 文件来源：本站录音，或用 Cambridge 录音补的缺口。 */
type Source = "yyb" | "cambridge";

interface Job {
  url: string;
  file: string; // 落盘文件名（见 makeFileName：ASCII 序号名，不由 IPA 派生）
  entry: Entry;
  source: Source;
  src: string; // 这个文件是从哪个源文件来的（yyb 站内 basename / Cambridge basename）
}

/**
 * 落盘文件名：`v01.mp3`…（元音）、`c01.mp3`…（辅音），序号 = 页面顺序。
 *
 * 为什么不沿用源站 basename（Cambridge 源是沿用的）：源站用的是 `I-long.mp3` /
 * `ə-long.mp3` / `eɪ.mp3` 这类含 IPA 字符的名字——macOS 默认大小写不敏感（`i` 与
 * `I` 会撞）、Unicode 又有 NFC/NFD 归一化差异，manifest 里的名字与实际文件名可能
 * 对不上。文件名只当不透明句柄用，**符号 → 文件的映射以 manifest.json 为准**，
 * 源站原名保留在 manifest 的 `src` 字段备查。
 */
function makeFileName(prefix: string, index: number): string {
  return `${prefix}${String(index).padStart(2, "0")}.mp3`;
}

// ---------------------------------------------------------------- 参数

interface Args {
  out: string;
  force: boolean;
  batch: number;
  delay: number;
  cambridge: string;
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    out: DEFAULT_OUT,
    force: false,
    batch: 6,
    delay: 150,
    cambridge: "",
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--force") args.force = true;
    else if (a === "--out") args.out = argv[++i] ?? args.out;
    else if (a === "--batch") args.batch = Math.max(1, Number(argv[++i]) || args.batch);
    else if (a === "--delay") args.delay = Math.max(0, Number(argv[++i]) || args.delay);
    else if (a === "--cambridge") args.cambridge = argv[++i] ?? args.cambridge;
    else if (a === "--no-cambridge") args.cambridge = "";
    else if (a === "--help" || a === "-h") {
      console.log(
        [
          "用法: bun run tool/fetch-phonetics-yyb.ts -- [选项]",
          "",
          "  --out <dir>        输出目录（缺省 assets/phonetics）",
          "  --force            重下已存在的文件（缺省跳过，断点续跑）",
          "  --batch N          每批取回的 URL 数（批内串行，缺省 6）",
          "  --delay MS         批内请求间隔（缺省 150）",
          "  --cambridge <dir>  Cambridge 源目录，用于补本站已删除的 18 个录音",
          "                     （无缺省；先用 fetch-phonetics.ts --out <临时目录> 生成）",
        ].join("\n"),
      );
      process.exit(0);
    } else throw new Error(`未知参数: ${a}`);
  }
  return args;
}

// ---------------------------------------------------------------- 页面

/** 页面就绪：出现第一个播放按钮（表格内容已渲染）。 */
const READY_SCRIPT = `!!document.querySelector("input.myButton_play")`;

/**
 * 页面内解析音标表。
 *
 * 源站用 compact-wp-audio-player 插件，音频不挂 `<audio>`，而是把地址塞进播放按钮的
 * onclick：`play_mp3('play','<随机id>','<mp3地址>','80','false')`。因此从 onclick 里
 * 取地址（停止按钮的地址为空串，按 class 只取播放按钮）。
 *
 * 音标符号在该 `<td>` 内、播放器容器**之前**的文本里（"清:/p/" 或 "/i:/ 详解 拼读 单词"），
 * 例词在容器**之后**（"see/she"）。按 DOM 顺序切分文本节点，比正则整段 HTML 稳。
 */
const EXTRACT_SCRIPT = `(() => {
  const clean = (s) => (s || "").replace(/\\s+/g, " ").trim();
  const rows = [];
  for (const td of document.querySelectorAll("td")) {
    const btn = td.querySelector("input.myButton_play");
    if (!btn) continue;
    const onclick = btn.getAttribute("onclick") || "";
    const m = onclick.match(/play_mp3\\(\\s*'play'\\s*,\\s*'[^']*'\\s*,\\s*'([^']+)'/);
    if (!m || !m[1]) continue;
    const url = m[1];

    // 按文档顺序把该单元格的文本节点切成「播放器之前」与「之后」两段。
    // 用 compareDocumentPosition 判先后，不能靠"走过播放器内部的文本节点"——播放器
    // 容器里全是 input/div，一个文本节点都没有（只有一段 HTML 注释，注释不进 TreeWalker）。
    const box = td.querySelector(".sc_player_container1");
    let before = "", after = "";
    const walker = document.createTreeWalker(td, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      // 直接拼接、不插空格：原标记里的空格就在文本节点里（"...<strong>ee</strong>" 拆出的
      // 节点拼回去才是原词），凭空加空格会把 "see" 拆成 "s ee"。
      const isAfter = !box || (box.compareDocumentPosition(n) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
      if (isAfter) after += n.nodeValue;
      else before += n.nodeValue;
    }
    const sym = clean(before).match(/\\/([^\\/]{1,8})\\//);
    if (!sym) continue;

    // 页内分组标题：往上找本行所属表格的表头第一行
    const tr = td.closest("tr");
    const table = td.closest("table");
    const head = table && table.querySelector("tr th");
    rows.push({
      symbol: sym[1],
      keyword: clean(after).slice(0, 40),
      table: clean(head && head.textContent).replace(/\\s+/g, " "),
      url: new URL(url, location.href).href,
    });
  }
  return rows;
})()`;

// ---------------------------------------------------------------- 主流程

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  console.log(`输出: ${args.out}`);
  console.log(`页面: ${PAGES.map((p) => p.label).join(" + ")} | 强制覆盖: ${args.force ? "是" : "否"}\n`);

  const view = new Bun.WebView({ width: 1440, height: 2000, ...viewOptions() });
  const jobs: Job[] = [];
  const seen = new Set<string>();
  // 上一轮 manifest 里记的来源：已存在的文件不重下，来源要沿用，不能被当成"本轮从本站下的"
  const prev = readPrevSources(args.out);

  try {
    for (const page of PAGES) {
      console.log(`→ ${page.url}`);
      const ready = await gotoAndWait(view, page.url, READY_SCRIPT);
      if (!ready) throw new Error(`${page.url} 30s 未渲染出播放按钮，页面结构可能已变`);

      const entries = await guard(view.evaluate<Entry[]>(EXTRACT_SCRIPT), "解析音标表", 30_000);
      console.log(`  解析到 ${entries.length} 个音标`);
      if (entries.length === 0) throw new Error(`${page.url} 解析为空，页面结构可能已变`);

      entries.forEach((entry, i) => {
        const file = makeFileName(page.prefix, i + 1);
        if (seen.has(file)) throw new Error(`文件名冲突: ${file}`);
        seen.add(file);
        const was = prev.get(file);
        jobs.push({
          url: entry.url,
          file,
          entry,
          source: was?.source ?? "yyb",
          src: was?.src ?? decodeURIComponent(entry.url.split("/").pop()!),
        });
      });
    }

    mkdirSync(args.out, { recursive: true });

    const todo = args.force ? jobs : jobs.filter((j) => !existsSync(join(args.out, j.file)));
    console.log(`\n待下载 ${todo.length} 个（清单 ${jobs.length}，已存在 ${jobs.length - todo.length}）\n`);

    if (todo.length) {
      const results = await downloadAll(view, todo, {
        out: args.out,
        batch: args.batch,
        delay: args.delay,
      });
      // 只有真正落盘成功的才算本站产物；失败的留给下面的 Cambridge 补齐
      const byFile = new Map(results.map((r, i) => [todo[i]!.file, r]));
      for (const job of jobs) {
        if (!existsSync(join(args.out, job.file))) continue;
        if (byFile.has(job.file)) job.source = byFile.get(job.file)!.ok ? "yyb" : job.source;
      }
      report(jobs, results);
    }

    fillFromCambridge(args, jobs);
    writeManifest(args, jobs);
    reportCoverage(args, jobs);
  } finally {
    try {
      view.close();
    } catch {
      /* 已关闭 */
    }
  }
}

/**
 * 用 Cambridge 源补齐本站已删除的录音。
 *
 * 背景：本站页面挂着的 48 个 mp3 里，有 18 个（文件名以非 ASCII 开头的那些）在服务器上
 * 已被删除——WordPress 媒体库里还留着记录，请求返回的是 WP 的 404 页。这不是抓取失败，
 * 换客户端/换编码/翻旧目录都拿不到，详见 README"覆盖率"一节。
 *
 * 补齐只填空缺（文件不在盘上才补），来源记进 manifest 的 `source`，不冒充本站录音。
 */
function fillFromCambridge(args: Args, jobs: Job[]): void {
  const missing = jobs.filter((j) => !existsSync(join(args.out, j.file)));
  if (!args.cambridge) {
    if (missing.length) {
      console.log(`\n缺口 ${missing.length} 个未补：本工具从站点只能取到 30 个，其余在源站已删除。`);
      console.log("  补齐需指定 Cambridge 源：");
      console.log("    bun run tool/fetch-phonetics.ts --out /tmp/cambridge-phonetics");
      console.log("    bun run tool/fetch-phonetics-yyb.ts --cambridge /tmp/cambridge-phonetics");
    }
    return;
  }

  const manifestPath = join(args.cambridge, "manifest.json");
  if (!existsSync(manifestPath)) {
    console.log(`\n缺口 ${missing.length} 个，但读不到 Cambridge 清单（${manifestPath}）——未补齐`);
    console.log("提示：bun run tool/fetch-phonetics.ts --out <临时目录>，再把该目录传给 --cambridge");
    return;
  }

  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
    phonemes: { symbol: string; keyword: string; uk?: { sound: string | null } }[];
  };
  const bySymbol = new Map<string, { file: string; keyword: string }>();
  for (const p of manifest.phonemes) {
    const file = p.uk?.sound;
    if (file) bySymbol.set(normSymbol(p.symbol), { file, keyword: p.keyword });
  }

  const filled: string[] = [];
  const unfilled: string[] = [];
  for (const job of jobs) {
    const exists = existsSync(join(args.out, job.file));
    // 已存在且来源是 Cambridge 的，顺带刷新 src（上一轮可能记的是本站那个死链名）
    if (exists && job.source !== "cambridge") continue;
    const hit = bySymbol.get(normSymbol(job.entry.symbol));
    const from = hit ? join(args.cambridge, hit.file) : "";
    if (!hit || !existsSync(from)) {
      if (!exists) unfilled.push(job.entry.symbol.trim());
      continue;
    }
    if (!exists) {
      console.log(`  补 ${job.file} /${job.entry.symbol.trim()}/ ← ${hit.file}`);
      copyFileSync(from, join(args.out, job.file));
      filled.push(`${job.file} /${job.entry.symbol.trim()}/`);
    }
    job.source = "cambridge";
    job.src = hit.file;
  }
  if (filled.length) {
    console.log(`\n补齐缺口 ${filled.length} 个（源: ${args.cambridge}，取 ${CAMBRIDGE_REGION}）`);
  }
  if (unfilled.length) console.log(`  仍缺 ${unfilled.length} 个: ${unfilled.map((s) => `/${s}/`).join(" ")}`);
}

/** manifest.json：符号 → 例词 → 文件，供 App/后续脚本按符号取用。 */
function writeManifest(args: Args, jobs: Job[]): void {
  const entries = jobs.map((j) => ({
    symbol: j.entry.symbol,
    normalized: normSymbol(j.entry.symbol),
    keyword: j.entry.keyword,
    table: j.entry.table,
    file: j.file,
    source: j.source,
    src: j.src,
    page: PAGES.find((p) => j.file.startsWith(p.prefix))!.url,
  }));
  const manifest = {
    source: PAGES.map((p) => p.url),
    fillSource: args.cambridge ? join(args.cambridge, "manifest.json") : null,
    fetchedAt: new Date().toISOString(),
    count: entries.length,
    phonemes: entries,
  };
  writeFileSync(join(args.out, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  const nYyb = entries.filter((e) => e.source === "yyb").length;
  console.log(
    `\nmanifest.json 已写入（${entries.length} 条：本站 ${nYyb}，Cambridge 补 ${entries.length - nYyb}）`,
  );
}

/** 读上一轮 manifest 的文件 → {来源, 源文件}，供"已存在文件不重下但仍要标注来源"用。 */
function readPrevSources(out: string): Map<string, { source: Source; src: string }> {
  const m = new Map<string, { source: Source; src: string }>();
  const p = join(out, "manifest.json");
  if (!existsSync(p)) return m;
  try {
    const json = JSON.parse(readFileSync(p, "utf8")) as {
      phonemes?: { file: string; source?: Source; src?: string }[];
    };
    for (const e of json.phonemes ?? []) {
      if (e.file && (e.source === "yyb" || e.source === "cambridge") && e.src) {
        m.set(e.file, { source: e.source, src: e.src });
      }
    }
  } catch {
    /* 清单损坏则视为无历史 */
  }
  return m;
}

/**
 * 归一化：源站写法 → App 的写法。
 *   i: → iː（长度符 ASCII 冒号 vs 修饰符字母）
 *   a: → ɑː（源站用 a，App 用 ɑ）
 *   ai → aɪ、əU → əʊ（源站混用大写/双字母写法）
 *   ɡ → g（U+0261 vs U+0067，同一音素）
 */
function normSymbol(s: string): string {
  return s
    .trim()
    .replace(/:/g, "ː")
    .replace(/əU/g, "əʊ")
    .replace(/ai/g, "aɪ")
    .replace(/aː/g, "ɑː")
    .replace(/\u0261/g, "g");
}

/** 读 App 的 phonicsGroups，得到需求符号清单（避免在脚本里重复维护一份）。 */
function readAppPhonemes(): string[] | null {
  if (!existsSync(APP_DATA)) return null;
  const src = readFileSync(APP_DATA, "utf8");
  const out: string[] = [];
  for (const m of src.matchAll(/PhonicsItem\(\s*phone:\s*'([^']+)'/g)) {
    out.push(normSymbol(m[1]!.replace(/^\/|\/$/g, "")));
  }
  return out.length ? out : null;
}

/** 本站下载结果（补齐前的原始战况）。 */
function report(jobs: Job[], fetched: { ok: boolean }[]): void {
  const okCount = fetched.filter((f) => f.ok).length;
  const failCount = fetched.length - okCount;
  console.log(`本站下载: 成功 ${okCount}，失败 ${failCount}` + (failCount ? "（见上方 ✗ 行）" : ""));
  if (failCount) console.log(`  失败原因见 README: 这些文件在源站已被删除（WP 库有记录、服务器无文件）`);
}

/** 覆盖率报告：抓到的符号 vs App 需求的 48 个。 */
function reportCoverage(args: Args, jobs: Job[]): void {
  const have = new Set(jobs.map((j) => normSymbol(j.entry.symbol)));
  const onDisk = jobs.filter((j) => existsSync(join(args.out, j.file)));
  console.log(
    `\n产出: ${onDisk.length}/${jobs.length} 个文件在盘上` +
      `（本站 ${onDisk.filter((j) => j.source === "yyb").length}，Cambridge 补 ${onDisk.filter((j) => j.source === "cambridge").length}）`,
  );

  const want = readAppPhonemes();
  if (!want) {
    console.log(`未读到 App 需求清单（${APP_DATA} 不存在或格式已变），跳过覆盖率报告`);
    return;
  }
  const missing = want.filter((w) => !have.has(w));
  console.log(`覆盖率: App 需要 ${want.length} 个，本站提供 ${want.length - missing.length} 个`);
  if (missing.length) console.log(`缺口 ${missing.length} 个: ${missing.map((m) => `/${m}/`).join(" ")}`);
  const extra = [...have].filter((h) => !want.includes(h));
  if (extra.length) console.log(`本站另有 ${extra.length} 个（App 未用）: ${extra.join(" ")}`);
}

await main();
