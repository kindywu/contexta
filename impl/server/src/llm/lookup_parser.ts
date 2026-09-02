// 移植 Rust src/llm/parser.rs 的 WordLookup 部分（parse_word_lookup）。
// 字段名即 App 端 JSON 契约（snake_case 与 Dart 原版一致）。

export interface ExampleOut {
  order_index: number;
  sentence_en: string;
  sentence_zh: string;
  is_primary: boolean;
}

export interface SenseOut {
  order_index: number;
  part_of_speech: string;
  chinese_meaning: string;
  english_definition: string;
  examples: ExampleOut[];
}

export interface WordLookup {
  spelling: string;
  phonetic: string | null;
  senses: SenseOut[];
}

/**
 * 移植 Dart `RegExp(r'<tag>([\s\S]*?)</tag>').firstMatch()?.group(1)?.trim()`：
 * 非贪婪首配 + trim；`\s*` 包裹等价于 trim 效果。
 */
function firstMatch(content: string, tag: string): string | null {
  const m = content.match(new RegExp(`<${tag}>\\s*([\\s\\S]*?)\\s*</${tag}>`));
  return m ? m[1].trim() : null;
}

/**
 * 移植 parseWordLlmResponse（含容错兜底）。
 *
 * 无 `<spelling>` 或内容为空时，用首个成对根标签的内容兜底为拼写
 * （如 `<ocean>ocean</ocean>`）；仅接受单词/词组形态（无标签、无换行），
 * 拒绝把 `<sense>`/`<phonetic>` 等结构块当拼写。JS 正则支持反向引用但
 * 语义不如 Rust 两步骤（取开标签名 → 找最早的对应闭标签）直观，此照搬。
 */
export function parseWordLookup(content: string): WordLookup | null {
  let spelling = firstMatch(content, "spelling");
  if (spelling === null || spelling === "") {
    // 容错：<ocean>ocean</ocean> 兜底（与 Dart 一致）
    const trimmed = content.trim();
    const open = trimmed.match(/^<([A-Za-z][A-Za-z\-]*)>/);
    if (open) {
      const tag = open[1];
      const openEnd = open[0].length;
      const closeStart = trimmed.indexOf(`</${tag}>`, openEnd);
      if (closeStart !== -1) {
        const candidate = trimmed.slice(openEnd, closeStart).trim();
        if (/^[A-Za-z][A-Za-z'\-]*( [A-Za-z][A-Za-z'\-]*)?$/.test(candidate)) {
          spelling = candidate;
        }
      }
    }
  }
  if (spelling === null || spelling === "") return null;

  const phonetic = firstMatch(content, "phonetic");

  const senseRe = /<sense>([\s\S]*?)<\/sense>/g;
  // 例句正则每轮复用（String.matchAll 内部克隆，不污染 senseRe 的 lastIndex）
  const exRe = /<example>([\s\S]*?)<\/example>/g;
  const senses: SenseOut[] = [];
  let senseIndex = 0;
  for (const sm of content.matchAll(senseRe)) {
    senseIndex++;
    const sc = sm[1];
    const examples: ExampleOut[] = [];
    let exIndex = 0;
    for (const em of sc.matchAll(exRe)) {
      exIndex++;
      const ec = em[1];
      examples.push({
        order_index: exIndex,
        sentence_en: firstMatch(ec, "en") ?? "",
        sentence_zh: firstMatch(ec, "zh") ?? "",
        is_primary: exIndex === 1,
      });
    }
    senses.push({
      order_index: senseIndex,
      part_of_speech: firstMatch(sc, "partOfSpeech") ?? "",
      chinese_meaning: firstMatch(sc, "chineseMeaning") ?? "",
      english_definition: firstMatch(sc, "englishDefinition") ?? "",
      examples,
    });
  }
  if (senses.length === 0) return null;
  return { spelling, phonetic, senses };
}
