/**
 * 音标录音导入（本地录音包 → App assets）——**App 参考页实际使用的那一套**。
 *
 * 2026-09 起素材换成人工提供的录音包（zip）：`音标/` 48 个音标本身 +
 * `例句/` 48 个例词，各为 16kHz 单声道 mp3。相比早先「音标网抓 30 + Cambridge 补 18」
 * 那套，这一包**音色统一**且**例词也有人声录音**（不再走 TTS）。
 *
 * 源包文件名形如 `音标/01_iː.mp3`、`例句/01_iː_see.mp3`——序号 + 符号 [+ 例词]。
 * 落盘改成纯 ASCII 序号（`s01.mp3` / `w01.mp3`）：macOS 大小写不敏感、Unicode 还有
 * NFC/NFD 差异，含 IPA 的文件名容易与清单对不上（符号 → 文件只认 manifest）。
 *
 * 用法：
 *   cd impl/server
 *   bun run tool/import-phonetics-audio.ts --zip <录音包.zip> [--out <dir>]
 *
 * 详见同目录 README.md 与 docs/phoneme-audio.md。
 */

import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { tmpdir } from "node:os";

/** 缺省输出目录：Flutter App 的 assets（tool 在 impl/server/tool）。 */
const DEFAULT_OUT = join(import.meta.dir, "..", "..", "app", "flutter", "assets", "phonetics");

/** App 需求清单的来源文件（相对仓库根）——覆盖率比对用，不在本脚本里重复维护。 */
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

interface Clip {
  /** 录音包里的序号，01 起。 */
  index: string;
  /** 音标符号（录音包写法，如 `iː`、`g`）。 */
  symbol: string;
  /** 例词（仅例句目录有）。 */
  keyword?: string;
  /** 源包内相对路径。 */
  src: string;
}

/** `01_iː.mp3` → { index: '01', symbol: 'iː' }；`01_iː_see.mp3` → 另带 keyword。 */
function parseName(file: string, withKeyword: boolean): Clip | null {
  const stem = basename(file, ".mp3");
  const parts = stem.split("_");
  if (parts.length < 2) return null;
  const [index, symbol, ...rest] = parts;
  if (!/^\d+$/.test(index) || !symbol) return null;
  if (withKeyword && rest.length === 0) return null;
  return { index, symbol, keyword: withKeyword ? rest.join("_") : undefined, src: file };
}

/** 读目录下的 mp3（跳过 macOS 的 `._` 资源叉与 .DS_Store）。 */
function readClips(dir: string, withKeyword: boolean, label: string): Clip[] {
  if (!existsSync(dir)) throw new Error(`录音包里没有 ${label} 目录：${dir}`);
  const out: Clip[] = [];
  for (const name of readdirSync(dir).sort()) {
    if (!name.endsWith(".mp3") || name.startsWith("._")) continue;
    const clip = parseName(join(dir, name), withKeyword);
    if (!clip) throw new Error(`${label} 文件名不符合 <序号>_<符号>[_<例词>].mp3：${name}`);
    out.push(clip);
  }
  return out;
}

/** 解压（zip 里是非 ASCII 文件名，`unzip` 会按 CP437 猜错编码，用 ditto 保 UTF-8）。 */
function extract(zip: string, dest: string): string {
  mkdirSync(dest, { recursive: true });
  const p = Bun.spawnSync(["ditto", "-x", "-k", zip, dest]);
  if (p.exitCode !== 0) throw new Error(`解压失败：${p.stderr.toString() || p.stdout.toString()}`);
  // 包里可能套一层目录（`ipa_audio/`），往里找「音标 / 例句」
  for (const entry of readdirSync(dest, { withFileTypes: true })) {
    if (entry.isDirectory() && existsSync(join(dest, entry.name, "音标"))) {
      return join(dest, entry.name);
    }
  }
  return dest;
}

/** 从 reference_data.dart 的 phonicsGroups 正则读出 App 需要的符号（避免两处清单漂移）。 */
function appSymbols(): string[] {
  const text = readFileSync(APP_DATA, "utf8");
  return [...text.matchAll(/PhonicsItem\(phone:\s*'\/([^/]+)\/'/g)].map((m) => m[1]);
}

/** 归一化：`ɡ`(U+0261) → `g`(U+0067)（与 App 的 normalizePhone 一致）。 */
const norm = (s: string) => s.replaceAll("\u0261", "g");

const argv = Bun.argv.slice(2);
const arg = (name: string): string | undefined => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
};

const zip = arg("zip");
if (!zip) {
  console.error("用法：bun run tool/import-phonetics-audio.ts --zip <录音包.zip> [--out <dir>]");
  process.exit(1);
}
const outDir = arg("out") ?? DEFAULT_OUT;

const work = join(tmpdir(), `ipa-import-${process.pid}`);
rmSync(work, { recursive: true, force: true });
const root = extract(zip, work);
const symbols = readClips(join(root, "音标"), false, "音标");
const words = readClips(join(root, "例句"), true, "例句");

// 例词按序号挂到对应符号上（两目录序号一一对应）
const wordByIndex = new Map(words.map((w) => [w.index, w]));
const missingWord = symbols.filter((s) => !wordByIndex.has(s.index));
if (missingWord.length) {
  throw new Error(`这些序号只有音标、没有例词录音：${missingWord.map((s) => s.index).join(" ")}`);
}
const orphanWord = words.filter((w) => !symbols.some((s) => s.index === w.index));
if (orphanWord.length) {
  throw new Error(`这些序号的例词没有对应音标：${orphanWord.map((w) => w.index).join(" ")}`);
}

// 落盘：s01.mp3…（音标本身）、w01.mp3…（例词），同名旧文件先清掉
mkdirSync(outDir, { recursive: true });
for (const name of readdirSync(outDir)) {
  if (/^[vc]\d+\.mp3$/.test(name)) rmSync(join(outDir, name)); // 旧素材（yyb/Cambridge 那套）
}
const phonemes = symbols.map((s) => {
  const file = `s${s.index}.mp3`;
  const wordFile = `w${s.index}.mp3`;
  cpSync(join(root, "音标", basename(s.src)), join(outDir, file));
  cpSync(join(root, "例句", basename(wordByIndex.get(s.index)!.src)), join(outDir, wordFile));
  return {
    symbol: s.symbol,
    normalized: s.symbol,
    keyword: wordByIndex.get(s.index)!.keyword!,
    file,
    wordFile,
  };
});

writeFileSync(
  join(outDir, "manifest.json"),
  `${JSON.stringify(
    {
      source: { pack: basename(zip), note: "真人录音：音标 48 + 例词 48（16kHz 单声道 mp3）" },
      count: phonemes.length,
      phonemes,
    },
    null,
    2,
  )}\n`,
);

// 覆盖率报告：App 的 48 个符号是否都被录音覆盖
const have = new Set(phonemes.map((p) => norm(p.normalized)));
const need = appSymbols();
const gaps = need.filter((s) => !have.has(norm(s)));
const extra = phonemes.filter((p) => !need.map(norm).includes(norm(p.normalized)));
const total = readdirSync(outDir).filter((n) => n.endsWith(".mp3")).length;

console.log(`音标 ${symbols.length} 个 / 例词 ${words.length} 个 → ${outDir}（mp3 共 ${total} 个）`);
console.log(`App 覆盖：${need.length - gaps.length}/${need.length}${gaps.length ? `，缺 ${gaps.join(" ")}` : ""}`);
if (extra.length) console.log(`包内多出（App 未用）：${extra.map((p) => p.normalized).join(" ")}`);
rmSync(work, { recursive: true, force: true });
process.exit(gaps.length ? 1 : 0);
