import 'package:contexta/ui/reading/word_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阅读页分词（findWordRanges）测试（移植 ReadingWordExtractionTest.kt）：
/// 语义与分词参考实现（Python findall: [a-zA-Z]+(?:['-][a-zA-Z]+)*）一致：
/// 兼容缩写、连字符复合词，忽略外围标点，段落末尾不带空格直接跟标点的单词也能完整提取。
///
/// 区间为 half-open (start, end)，`text.substring(start, end)` 即得单词。

List<String> wordsOf(String text) => [
      for (final range in findWordRanges(text))
        text.substring(range.$1, range.$2)
    ];

void main() {
  test('extracts contractions hyphenated compounds and punctuation-glued words',
      () {
    // 复杂测试段落（同参考实现，弯引号/弯撇号已规范化为 ASCII）：
    // 引号、括号、破折号、缩写、粘连标点、复合词、多符号混杂
    const complexText = """
When you're chasing your dreams, don't fear temporary failures—they aren't permanent roadblocks.
The state-of-the-art device, designed by young engineers, can fix most common bugs: lag, crash, overload.
"I've tried dozens of methods," she said, "but nobody's solution works better than simple persistence."
Humanity's greatest strength isn't talent, but our never-give-up spirit!
Tomorrow's plan: review notes, finish homework, join the after-school club.
""";
    final words = wordsOf(complexText);
    expect(words, const [
      "When", "you're", "chasing", "your", "dreams", "don't", "fear",
      "temporary", "failures", "they", "aren't", "permanent", "roadblocks",
      "The", "state-of-the-art", "device", "designed", "by", "young",
      "engineers", "can", "fix", "most", "common", "bugs", "lag", "crash",
      "overload",
      "I've", "tried", "dozens", "of", "methods", "she", "said", "but",
      "nobody's", "solution", "works", "better", "than", "simple",
      "persistence",
      "Humanity's", "greatest", "strength", "isn't", "talent", "but", "our",
      "never-give-up", "spirit",
      "Tomorrow's", "plan", "review", "notes", "finish", "homework", "join",
      "the", "after-school", "club",
    ]);
  });

  test('paragraph final words with trailing punctuation are extracted', () {
    // 回归：段落最后一个单词后面无空格直接跟标点（修复前 token 带标点导致不可点击）
    const text = "Learn a new word every day. Practice makes progress.";
    expect(
      wordsOf(text),
      const ["Learn", "a", "new", "word", "every", "day", "Practice", "makes",
          "progress"],
    );
  });

  test('lone punctuation and dashes are not words', () {
    expect(wordsOf('—'), isEmpty);
    expect(wordsOf('-'), isEmpty);
    expect(wordsOf("'"), isEmpty);
    expect(wordsOf('"\'--"'), isEmpty);
  });

  test('word ranges reconstruct the original text without losing characters',
      () {
    const text = 'Hello, world! ("I\'m fine.") — Really?"OK"';
    final buffer = StringBuffer();
    var cursor = 0;
    for (final range in findWordRanges(text)) {
      buffer.write(text.substring(cursor, range.$1));
      buffer.write(text.substring(range.$1, range.$2));
      cursor = range.$2;
    }
    buffer.write(text.substring(cursor));
    expect(buffer.toString(), text);
  });
}
