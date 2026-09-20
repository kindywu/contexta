/**
 * 音标发音抓取：从 Cambridge Dictionary 的 Pronunciation symbols 页
 * （/us/help/phonetics.html）抓 48 音标的发音 mp3，供 App 参考页使用。
 *
 * 为什么走 Bun.WebView 而不是 fetch/curl：目标站点对非浏览器客户端会拒（或返回
 * 拦截页），而 mp3 位于 dictionary.cambridge.org 同源路径下——在**页面上下文里**
 * fetch 既带上了浏览器自身的 UA / Cookie / TLS 指纹，又不触发 CORS。这是本项目
 * 抓站的一贯做法（见 src/engine/sites/common.ts）。
 *
 * 音标表两处来源：
 *   - 页面上 Vowels / Consonants 两张表 = 抓取源（符号、例词、音频 URL）
 *   - App 的 phonicsGroups（impl/app/flutter/lib/ui/reference/reference_data.dart）
 *     = 需求方（恰好 48 个）。两者按符号比对，缺口在报告里列出。
 *   目前缺口恒为 /tr/ /dr/ /ts/ /dz/——它们不是 IPA 音素而是中国教材单列的音丛，
 *   Cambridge 页面没有独立录音，App 侧需继续用 TTS 拟音兜底。
 *
 * 用法：
 *   cd impl/server
 *   bun run tool/fetch-phonetics.ts -- [--out <dir>] [--force] [--regions uk,us]
 *
 * 详见同目录 README.md。
 */

import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  downloadAll,
  gotoAndWait,
  guard,
  viewOptions,
  type FetchResult,
} from "./lib/webview";

const PAGE_URL = "https://dictionary.cambridge.org/us/help/phonetics.html";

/**
 * 输出目录**必须显式指定**（`--out <dir>`）。
 *
 * 为什么不留默认值：App 实际使用的是 `fetch-phonetics-yyb.ts` 那套（48/48，落在
 * `assets/phonetics/`），它已经把这 176 个文件里用得到的 18 个固化进 App 素材。
 * 本工具现在只作为那道补齐的素材源，若默认写进 `assets/phonetics/`，跑一次就会把
 * 176 个 Cambridge 文件倒进 App 的素材目录——两者同名不同源，必须物理隔离。
 */

/** App 需求清单的来源文件（相对仓库根）。 */
const APP_DATA = join(
  import.meta.dir, "..", "..", "app", "flutter", "lib", "ui", "reference", "reference_data.dart",
);

/** 页面上解析出的一个音标条目。 */
interface Phoneme {
  symbol: string; // IPA 符号，如 "iː" / "tʃ"
  keyword: string; // 例词，如 "sheep"
  table: string; // vowels | consonants
  sound: Region; // 音素本身的录音
  word: Region; // 例词的录音
}

interface Region {
  uk: string | null;
  us: string | null;
}

interface Job {
  url: string;
  file: string; // 落盘文件名（沿用 Cambridge 自己的 basename，天然唯一）
}

// ---------------------------------------------------------------- 参数

interface Args {
  out: string;
  force: boolean;
  regions: ("uk" | "us")[];
  batch: number;
  delay: number;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { out: "", force: false, regions: ["uk", "us"], batch: 6, delay: 150 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--force") args.force = true;
    else if (a === "--out") args.out = argv[++i] ?? args.out;
    else if (a === "--batch") args.batch = Math.max(1, Number(argv[++i]) || args.batch);
    else if (a === "--delay") args.delay = Math.max(0, Number(argv[++i]) || 0);
    else if (a === "--regions") {
      const list = (argv[++i] ?? "").split(",").map((s) => s.trim().toLowerCase());
      const bad = list.filter((r) => r !== "uk" && r !== "us");
      if (bad.length) throw new Error(`--regions 只接受 uk / us，收到: ${bad.join(",")}`);
      args.regions = list as ("uk" | "us")[];
    } else if (a === "--help" || a === "-h") {
      console.log(
        [
          "用法: bun run tool/fetch-phonetics.ts -- --out <dir> [--force] [--regions uk,us] [--batch N] [--delay MS]",
          "",
          "  --out <dir>  必填。本工具输出不随仓库携带，建议放临时目录，例如：",
          "                 bun run tool/fetch-phonetics.ts --out /tmp/cambridge-phonetics",
          "               （App 用的那套是 fetch-phonetics-yyb.ts，输出到 assets/phonetics/）",
        ].join("\n"),
      );
      process.exit(0);
    } else throw new Error(`未知参数: ${a}`);
  }
  if (!args.out) {
    throw new Error("必须指定 --out <dir>（如 --out /tmp/cambridge-phonetics）；用 --help 看说明");
  }
  return args;
}

// ---------------------------------------------------------------- 视图

/**
 * 页面内解析音标表。在浏览器里做（而非在外层正则 HTML）的好处：
 * 拿到的就是 DOM 语义（行列、source 的 type），不依赖属性顺序与空白。
 */
const EXTRACT_SCRIPT = `(() => {
  const rows = [];
  for (const table of document.querySelectorAll("table")) {
    const summary = (table.getAttribute("summary") || "").toLowerCase();
    if (summary !== "vowels" && summary !== "consonants") continue;
    for (const tr of table.querySelectorAll("tbody tr")) {
      const tds = tr.querySelectorAll("td");
      if (tds.length < 4) continue;
      const text = (el) => (el.textContent || "").replace(/\\s+/g, " ").trim();
      const pick = (td) => {
        const r = { uk: null, us: null };
        for (const src of td.querySelectorAll("source[type='audio/mpeg']")) {
          const raw = src.getAttribute("src") || "";
          if (!raw) continue;
          const url = new URL(raw, location.origin).href;
          if (url.includes("/uk_phonetic/")) r.uk = url;
          else if (url.includes("/us_phonetic/")) r.us = url;
        }
        return r;
      };
      const symbol = text(tds[0]);
      const keyword = text(tds[2]);
      const sound = pick(tds[1]);
      const word = pick(tds[3]);
      if (!sound.uk && !sound.us && !word.uk && !word.us) continue;
      rows.push({ symbol, keyword, table: summary, sound, word });
    }
  }
  return rows;
})()`;

/** 轮询直到音标表渲染出来（软导航后 DOM 才是准的）。 */
const READY_SCRIPT = `!!document.querySelector("table[summary='Vowels' i], table[summary='Consonants' i]")`;

// ---------------------------------------------------------------- 主流程

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  console.log(`页面: ${PAGE_URL}`);
  console.log(`输出: ${args.out}`);
  console.log(`区域: ${args.regions.join(", ")} | 强制覆盖: ${args.force ? "是" : "否"}\n`);

  const view = new Bun.WebView({ width: 1440, height: 2000, ...viewOptions() });
  let phonemes: Phoneme[] = [];
  const fetched: FetchResult[] = [];

  try {
    // 软导航 + 轮询（见 lib/webview.ts 的 gotoAndWait）。
    const ready = await gotoAndWait(view, PAGE_URL, READY_SCRIPT);
    if (!ready) throw new Error("音标表 30s 未渲染，页面结构可能已变");

    phonemes = await guard(
      view.evaluate<Phoneme[]>(EXTRACT_SCRIPT),
      "解析音标表",
      30_000,
    );
    console.log(`解析到 ${phonemes.length} 个音标条目\n`);
    if (phonemes.length === 0) throw new Error("音标表解析为空，页面结构可能已变");

    // 组装下载清单：音素声 + 例词声 × 所选区域
    const jobs: Job[] = [];
    const seen = new Set<string>();
    for (const p of phonemes) {
      for (const region of args.regions) {
        for (const kind of ["sound", "word"] as const) {
          const url = p[kind][region];
          if (!url) continue;
          const file = url.split("/").pop()!;
          if (seen.has(file)) continue;
          seen.add(file);
          jobs.push({ url, file });
        }
      }
    }

    const todo = args.force
      ? jobs
      : jobs.filter((j) => !existsSync(join(args.out, j.file)));
    console.log(`待下载 ${todo.length} 个文件（清单 ${jobs.length}，已存在 ${jobs.length - todo.length}）\n`);

    mkdirSync(args.out, { recursive: true });

    fetched.push(
      ...(await downloadAll(view, todo, { out: args.out, batch: args.batch, delay: args.delay })),
    );
  } finally {
    try {
      view.close();
    } catch {
      /* 已关闭 */
    }
  }

  writeManifest(args, phonemes);
  report(args, phonemes, fetched);
}

/** 写 manifest.json：符号 → 例词 → 文件，供 App/后续脚本按符号取用。 */
function writeManifest(args: Args, phonemes: Phoneme[]): void {
  const entries = phonemes.map((p) => {
    const rel = (url: string | null) => (url ? url.split("/").pop()! : null);
    const region: Record<string, unknown> = {};
    for (const r of args.regions) {
      region[r] = { sound: rel(p.sound[r]), word: rel(p.word[r]) };
    }
    return { symbol: p.symbol, keyword: p.keyword, table: p.table, ...region };
  });
  const manifest = {
    source: PAGE_URL,
    fetchedAt: new Date().toISOString(),
    regions: args.regions,
    count: entries.length,
    phonemes: entries,
  };
  writeFileSync(join(args.out, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  console.log(`\nmanifest.json 已写入（${entries.length} 条）`);
}

/** 归一化符号：App 用 ɡ(U+0261)、Cambridge 用 g(U+0067)，同一音素。 */
const normSymbol = (s: string) => s.replace(/\u0261/g, "g").trim();

/** 读 App 的 phonicsGroups，得到需求符号清单（避免在脚本里重复维护一份）。 */
function readAppPhonemes(): string[] | null {
  if (!existsSync(APP_DATA)) return null;
  const src = readFileSync(APP_DATA, "utf8");
  const out: string[] = [];
  for (const m of src.matchAll(/PhonicsItem\(\s*phone:\s*'([^']+)'/g)) {
    const raw = m[1]!.replace(/^\/|\/$/g, "");
    out.push(normSymbol(raw));
  }
  return out.length ? out : null;
}

/** 覆盖率报告：抓到的符号 vs App 需求的 48 个。 */
function report(args: Args, phonemes: Phoneme[], fetched: FetchResult[]): void {
  const okCount = fetched.filter((f) => f.ok).length;
  const failCount = fetched.length - okCount;
  console.log(
    `\n下载: 成功 ${okCount}，失败 ${failCount}` + (failCount ? "（见上方 ✗ 行）" : ""),
  );

  const have = new Set(phonemes.map((p) => normSymbol(p.symbol)));
  const want = readAppPhonemes();
  if (!want) {
    console.log(`\n未读到 App 需求清单（${APP_DATA} 不存在或格式已变），跳过覆盖率报告`);
    return;
  }
  const missing = want.filter((w) => !have.has(w));
  console.log(`\n覆盖率: App 需要 ${want.length} 个，Cambridge 提供 ${want.length - missing.length} 个`);
  if (missing.length) {
    console.log(`缺口 ${missing.length} 个: ${missing.map((m) => `/${m}/`).join(" ")}`);
    console.log("（这些不是 IPA 音素而是中国教材单列的音丛，Cambridge 无独立录音，App 侧继续用 TTS 拟音兜底）");
  }
  // Cambridge 有、App 48 个里没有的（美式变体等），一并列出便于将来扩展
  const extra = [...have].filter((h) => !want.includes(h));
  if (extra.length) console.log(`Cambridge 另有 ${extra.length} 个（App 未用）: ${extra.join(" ")}`);
}

await main();
