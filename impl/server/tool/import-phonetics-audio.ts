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
 * 另有 `--phonemes-from` 模式：**只换 48 个音标本身**，例词与清单原样不动。
 * 用于从外部音标站（`ipa_web`，见下）取更准的音标读音：
 *
 *   bun run tool/import-phonetics-audio.ts --phonemes-from <ipa_web 目录> [--out <dir>]
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

// ---------------------------------------------------------------------------
// `--phonemes-from`：只换 48 个音标本身（例词与清单映射不动）
// ---------------------------------------------------------------------------

/**
 * 音标录音的转码目标规格。采样率**不降到 16kHz**（例词那套是 16k）：
 * /s/ /ʃ/ /f/ /θ/ 这些擦音的能量集中在 4kHz 以上，降到 16k 先把它们磨钝——
 * 而换这一包图的就是读音准。体积代价可忽略：assets 一共 66MB
 * （TTS 模型 43MB + 库 23MB），48 个音标 44.1kHz 单声道 96kbps 约 460KB。
 */
const PHONEME_RATE = "44100";
const PHONEME_BITRATE = "96";

interface ManifestEntry {
  symbol: string;
  normalized: string;
  keyword: string;
  file: string;
  wordFile: string;
}

/** 读 `ipa_web` 目录的 meta.json：符号 → 音频绝对路径（外加出处，写进清单用）。 */
function readSymbolAudioDir(dir: string): { bySymbol: Map<string, string>; origin: string } {
  const metaPath = join(dir, "meta.json");
  if (!existsSync(metaPath)) throw new Error(`源目录里没有 meta.json：${metaPath}`);
  const meta = JSON.parse(readFileSync(metaPath, "utf8")) as {
    source?: string;
    symbols?: { symbol?: string; audio?: string }[];
  };
  const bySymbol = new Map<string, string>();
  for (const entry of meta.symbols ?? []) {
    if (typeof entry?.symbol !== "string" || typeof entry?.audio !== "string") continue;
    bySymbol.set(norm(entry.symbol), join(dir, entry.audio));
  }
  if (!bySymbol.size) throw new Error(`meta.json 里没读到 symbols[].audio：${metaPath}`);
  return { bySymbol, origin: meta.source ?? dir };
}

/**
 * ADTS-AAC → MP3（44.1kHz 单声道，不裁静音、不动响度）。
 *
 * 源文件是 **ADTS AAC 却挂着 .mp3 扩展名**（`file` 认作 `MPEG ADTS, AAC, v4 LC`）。
 * CoreAudio 按扩展名挑解析器，`.mp3` 一律打不开——`afinfo` 与直接喂给 `afconvert`
 * 都报 "Couldn't open input file"。**必须先复制成 .aac 再解码**，否则整批静默失败。
 * （同理，这包音频也**不能原样进 App**：App 侧同样打不开。）
 */
function transcodePhoneme(src: string, out: string, work: string): void {
  const aac = join(work, "in.aac");
  const wav = join(work, "in.wav");
  cpSync(src, aac);
  const decode = Bun.spawnSync([
    "afconvert", "-f", "WAVE", "-d", `LEI16@${PHONEME_RATE}`, "-c", "1", aac, wav,
  ]);
  if (decode.exitCode !== 0) {
    throw new Error(`解码失败 ${basename(src)}：${decode.stderr.toString().trim()}`);
  }
  const encode = Bun.spawnSync(["lame", "--quiet", "-b", PHONEME_BITRATE, "-m", "m", wav, out]);
  if (encode.exitCode !== 0) {
    throw new Error(`编码失败 ${basename(src)}：${encode.stderr.toString().trim()}`);
  }

  // **光看退出码不够**：afconvert 遇到挂 .mp3 扩展名的 ADTS 时退出码 0、stderr 空，
  // 却只写出一段 0.057s 的碎片（0.95s 的源 → 5KB wav）。这种「静默截断」一旦漏进去，
  // App 里表现成「点了没声」，排查成本极高——所以回读产物验长度。
  const seconds = mp3Duration(out);
  if (seconds === null || seconds < 0.2) {
    throw new Error(
      `产物可疑：${basename(out)} 时长 ${seconds ?? "读不出"}s ← ${basename(src)}`,
    );
  }
}

/** 读 mp3 时长（秒）；读不出返回 null。 */
function mp3Duration(path: string): number | null {
  const p = Bun.spawnSync(["afinfo", path]);
  const m = p.stdout.toString().match(/estimated duration:\s*([\d.]+)/);
  return m ? Number(m[1]) : null;
}

/**
 * 按**符号**把清单里每个音标的 `file` 换掉（`wordFile` 与 phonemes 映射一字不动）。
 *
 * 按符号而非按位置：App 的 `phonicsGroups` 顺序（… ɑː ɒ ɔː ʊ uː ʌ ɜː ə …）与清单
 * 顺序（… ʌ ɜː ə uː ʊ ɔː ɒ ɑː …）**不同**，按位置整体错位，发音会张冠李戴。
 *
 * 覆盖先校验后写入：源里缺任何一个符号就整体退出，不留半新半旧的包。
 */
function replacePhonemes(dir: string, outDir: string): void {
  const manifestPath = join(outDir, "manifest.json");
  if (!existsSync(manifestPath)) {
    throw new Error(`没有现成清单，先用 --zip 模式导入整套：${manifestPath}`);
  }
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
    source?: unknown;
    phonemes?: ManifestEntry[];
  };
  const phonemes = manifest.phonemes ?? [];
  if (!phonemes.length) throw new Error(`清单里没有 phonemes：${manifestPath}`);

  const { bySymbol, origin } = readSymbolAudioDir(dir);

  // ① 先校验覆盖，缺一个就不动手
  const missing = phonemes
    .filter((p) => !bySymbol.has(norm(p.normalized ?? p.symbol)))
    .map((p) => p.symbol);
  if (missing.length) {
    throw new Error(`源里缺这 ${missing.length} 个音标，未替换任何文件：${missing.join(" ")}`);
  }
  const orphan = [...bySymbol.keys()].filter((s) => !phonemes.some((p) => norm(p.normalized) === s));
  if (orphan.length) {
    console.log(`源里多出（App 未用，忽略）：${orphan.join(" ")}`);
  }

  // ② 转码（临时目录复用，逐个覆盖 in.aac / in.wav）
  const work = join(tmpdir(), `ipa-replace-${process.pid}`);
  rmSync(work, { recursive: true, force: true });
  mkdirSync(work, { recursive: true });
  for (const p of phonemes) {
    transcodePhoneme(bySymbol.get(norm(p.normalized))!, join(outDir, p.file), work);
  }
  rmSync(work, { recursive: true, force: true });

  // ③ 只更出处：phonemes 映射（符号 → sNN / wNN）保持不变
  const today = new Date().toISOString().slice(0, 10);
  manifest.source = {
    pack: "ipa_audio.zip",
    note:
      `音标（s*.mp3）取自 ${origin}，${today} 起用，${PHONEME_RATE}Hz 单声道 ` +
      `${PHONEME_BITRATE}kbps、未裁静音未归一响度；例词（w*.mp3）沿用人工录音包（16kHz 单声道 mp3）`,
  };
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const count = readdirSync(outDir).filter((n) => n.endsWith(".mp3")).length;
  console.log(`音标 ${phonemes.length} 个已按符号替换 → ${outDir}（mp3 共 ${count} 个，例词未动）`);
  console.log(`来源：${origin}`);
}

const argv = Bun.argv.slice(2);
const arg = (name: string): string | undefined => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
};

const zip = arg("zip");
const phonemesFrom = arg("phonemes-from");
const outDir = arg("out") ?? DEFAULT_OUT;

if (!zip && !phonemesFrom) {
  console.error(
    "用法：bun run tool/import-phonetics-audio.ts --zip <录音包.zip> [--out <dir>]\n" +
      "      bun run tool/import-phonetics-audio.ts --phonemes-from <ipa_web 目录> [--out <dir>]",
  );
  process.exit(1);
}

// 换音标：只动 s*.mp3，例词与清单映射保持原样
if (phonemesFrom) {
  try {
    replacePhonemes(phonemesFrom, outDir);
  } catch (e) {
    console.error(String(e instanceof Error ? e.message : e));
    process.exit(1);
  }
  process.exit(0);
}

if (!zip) process.exit(1); // 上面的用法检查已排除；仅为收窄类型

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
