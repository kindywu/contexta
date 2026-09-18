import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

import '../../core/theme/app_colors.dart';
import 'word_extractor.dart';

/// 朗读句底色（与生词高亮同色：生词 span 覆盖为珊瑚色后自然融合）。
const TextStyle kSpeakingStyle = TextStyle(
  backgroundColor: Color(0x2ECC785C),
);

/// 按单词区间切分文本生成 spans：单词 → 可点击 span（生词珊瑚底色），
/// 空白/标点原样保留。正文段落与文章标题共用。
///
/// [speakingRange] 为正在朗读的句子区间（half-open，含句末标点；null = 无），
/// 区间内文字追加 [kSpeakingStyle] 底色——句子边界可能落在 gap（空白/标点）
/// 内部，故 gap 按区间边界再切段；生词 span 保持珊瑚底色（同色系融合）。
/// [style] 为区间外文字的基础样式（null = 继承外层）。
///
/// [recognizerFor] 为 null 时**不挂手势**——分页测量走这条路径，避免为测量
/// 创建永不释放的 TapGestureRecognizer。
List<InlineSpan> buildWordSpans({
  required String text,
  TextStyle? style,
  required Set<String> vocabularyWords,
  TapGestureRecognizer Function(String word)? recognizerFor,
  (int, int)? speakingRange,
}) {
  final spans = <InlineSpan>[];

  bool inSpeaking(int offset) =>
      speakingRange != null &&
      offset >= speakingRange.$1 &&
      offset < speakingRange.$2;

  /// 追加 [from, to) 的纯文本片段，按朗读区间边界切成「底色 / 非底色」段。
  void addPlain(int from, int to) {
    var cursor = from;
    while (cursor < to) {
      final speaking = inSpeaking(cursor);
      var end = cursor + 1;
      while (end < to && inSpeaking(end) == speaking) {
        end++;
      }
      spans.add(
        TextSpan(
          text: text.substring(cursor, end),
          style: speaking ? kSpeakingStyle : style,
        ),
      );
      cursor = end;
    }
  }

  var cursor = 0;
  for (final range in findWordRanges(text)) {
    addPlain(cursor, range.$1);
    final word = text.substring(range.$1, range.$2);
    final normalized = word.toLowerCase();
    spans.add(
      TextSpan(
        text: word,
        style: vocabularyWords.contains(normalized)
            ? const TextStyle(
                color: AppColors.ink,
                backgroundColor: Color(0x2ECC785C),
              )
            : (inSpeaking(range.$1) ? kSpeakingStyle : style),
        recognizer: recognizerFor?.call(normalized),
      ),
    );
    cursor = range.$2;
  }
  addPlain(cursor, text.length);
  return spans;
}
