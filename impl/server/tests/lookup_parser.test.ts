// tests/lookup_parser.test.ts
import { describe, expect, test } from "bun:test";
import { parseWordLookup } from "../src/llm/lookup_parser";

describe("parseWordLookup", () => {
  test("标准 XML 全字段解析", () => {
    const xml = `<spelling>ocean</spelling><phonetic>/ˈoʊʃən/</phonetic>
<sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>海洋</chineseMeaning><englishDefinition>a large body of water</englishDefinition>
<example><en>The ocean is deep.</en><zh>海洋很深。</zh></example>
<example><en>They sailed the ocean.</en><zh>他们航行过海洋。</zh></example></sense>`;
    const r = parseWordLookup(xml)!;
    expect(r.spelling).toBe("ocean");
    expect(r.phonetic).toBe("/ˈoʊʃən/");
    expect(r.senses).toHaveLength(1);
    expect(r.senses[0].part_of_speech).toBe("n.");
    expect(r.senses[0].examples).toHaveLength(2);
    expect(r.senses[0].examples[0].is_primary).toBe(true);
    expect(r.senses[0].examples[1].is_primary).toBe(false);
  });
  test("缺 spelling 用根标签兜底（ocean）", () => {
    const xml = `<ocean>ocean</ocean><sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>海洋</chineseMeaning><englishDefinition>body of water</englishDefinition></sense>`;
    expect(parseWordLookup(xml)?.spelling).toBe("ocean");
  });
  test("多义项 order_index 1 起递增", () => {
    const xml = `<spelling>bank</spelling><sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>银行</chineseMeaning><englishDefinition>a financial institution</englishDefinition></sense><sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>河岸</chineseMeaning><englishDefinition>land alongside a river</englishDefinition></sense>`;
    const r = parseWordLookup(xml)!;
    expect(r.senses.map((s) => s.order_index)).toEqual([1, 2]);
  });
  test("空义项 / 无根标签 → null", () => {
    expect(parseWordLookup("<spelling>x</spelling>")).toBeNull();
    expect(parseWordLookup("plain text")).toBeNull();
  });
  test("缺 phonetic 容忍", () => {
    const xml = `<spelling>apple</spelling><sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>苹果</chineseMeaning><englishDefinition>a fruit</englishDefinition></sense>`;
    expect(parseWordLookup(xml)?.phonetic).toBeNull();
  });
});
