/// 阅读页内容块：书页分页以「块」为最小装载单位，**块内不切分**。
///
/// 只在块边界分页的依据：本 app 文章段落很短（75 篇统计：均 108 字符、
/// 最大 441、每篇 3–21 段），段落级分页最坏只损失一点页尾空白，却省掉了
/// 段落劈半带来的 span 切片、译文归属、句子高亮跨页三类复杂度。
sealed class ReadingBlock {
  const ReadingBlock();
}

/// 文章标题（其高度已含标题下的分隔线与间距）。
class TitleBlock extends ReadingBlock {
  const TitleBlock(this.text);
  final String text;
}

/// 一个段落：[index] 为段落序号（句子高亮 / 查词 / 自动翻页按它回查）。
class ParagraphBlock extends ReadingBlock {
  const ParagraphBlock({
    required this.index,
    required this.englishText,
    required this.chineseTranslation,
  });
  final int index;
  final String englishText;
  final String chineseTranslation;
}

/// 「标记已读」按钮（文章已读后不产生此块）。
class MarkAsReadBlock extends ReadingBlock {
  const MarkAsReadBlock();
}
