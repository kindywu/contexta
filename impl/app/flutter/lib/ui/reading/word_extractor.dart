/// 阅读正文单词匹配（对照 Kotlin ReadingScreen.kt 的 WORD_REGEX / findWordRanges）。
///
/// 兼容缩写（I'm、don't）与连字符复合词（state-of-the-art），首字符必须是字母，
/// 因此孤立标点（-、'）不会误判为单词。区间为 half-open (start, end)，
/// 与 Dart substring 语义一致（Kotlin IntRange 为闭区间，移植时换算）。
library;

/// 单词匹配规则（与分词参考实现 findall 语义一致）。
final RegExp _wordRegex = RegExp("[A-Za-z]+(?:['-][A-Za-z]+)*");

/// 在原文中查找所有单词的区间 (start, end)，单词间允许任意非单词字符
/// （空格、标点、破折号）。段落末尾不带空格直接跟标点的单词（如 "dreams."）
/// 也能完整提取——这是按空白切分 + 整 token 全量匹配方案做不到的
/// （token 含标点导致整段被判为非单词、不可点击）。
List<(int, int)> findWordRanges(String text) => [
      for (final match in _wordRegex.allMatches(text)) (match.start, match.end)
    ];
