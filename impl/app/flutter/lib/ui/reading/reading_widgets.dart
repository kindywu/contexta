import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'reading_controller.dart';
import 'translation_visibility.dart';
import 'word_spans.dart';

/// 文章标题：分词可点击查词 + 朗读时高亮（-1 哨兵，与正文同色）。
/// 与 [ReadingParagraph] 同样由 StatefulWidget 持有 TapGestureRecognizer，
/// dispose 时统一释放。
class ReadingTitle extends StatefulWidget {
  const ReadingTitle({
    super.key,
    required this.text,
    required this.isSpeaking,
    required this.vocabularyWords,
    required this.onWordClick,
  });

  final String text;
  final bool isSpeaking;
  final Set<String> vocabularyWords;
  final ValueChanged<String> onWordClick;

  @override
  State<ReadingTitle> createState() => ReadingTitleState();
}

class ReadingTitleState extends State<ReadingTitle> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  TapGestureRecognizer _wordRecognizer(String word) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onWordClick(word);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    // 朗读中标题整段加同色底色（标题是单个朗读单元，区间 = 全文）；gap/
    // 生词 span 继承或覆盖，见 buildWordSpans。Align 使标题在 ListView
    // 的 tight 交叉轴约束下 shrink-wrap（与正文段落一致），文字区域才是可点区域。
    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: AppType.readingTitle.copyWith(
            backgroundColor: widget.isSpeaking
                ? kSpeakingStyle.backgroundColor
                : null,
          ),
          children: buildWordSpans(
            text: widget.text,
            style: widget.isSpeaking ? kSpeakingStyle : null,
            vocabularyWords: widget.vocabularyWords,
            recognizerFor: _wordRecognizer,
          ),
        ),
      ),
    );
  }
}

/// 单个段落：可点击分词 + 内联播放图标 + 译文（对照 Kotlin ReadingParagraph）。
/// StatefulWidget 持有分词 TapGestureRecognizer，dispose 时统一释放。
class ReadingParagraph extends StatefulWidget {
  const ReadingParagraph({
    super.key,
    required this.textKey,
    required this.englishText,
    required this.chineseTranslation,
    required this.sentences,
    required this.speakingSentenceIndex,
    required this.translationMode,
    required this.isRevealed,
    required this.vocabularyWords,
    required this.isSpeaking,
    required this.onWordClick,
    required this.onTranslationClick,
    required this.onPlay,
  });

  /// 英文正文 RichText 的 key（ReadingScreen 按句滚动取文字盒坐标用）。
  final Key textKey;
  final String englishText;
  final String chineseTranslation;
  final List<ArticleSentence> sentences;

  /// 正在朗读的段内句序号（null = 本段未在朗读）。
  final int? speakingSentenceIndex;
  final TranslationMode translationMode;
  final bool isRevealed;
  final Set<String> vocabularyWords;
  final bool isSpeaking;
  final ValueChanged<String> onWordClick;
  final VoidCallback onTranslationClick;
  final VoidCallback onPlay;

  @override
  State<ReadingParagraph> createState() => ReadingParagraphState();
}

class ReadingParagraphState extends State<ReadingParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  TapGestureRecognizer _wordRecognizer(String word) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onWordClick(word);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 英文正文：按单词区间切分，单词可点击，单词间空白/标点原样保留
        RichText(
          key: widget.textKey,
          text: TextSpan(
            style: AppType.readingBody,
            children: [
              ..._buildAnnotatedSpans(),
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(width: 4),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _InlinePlayButton(
                  isSpeaking: widget.isSpeaking,
                  onClick: widget.onPlay,
                ),
              ),
            ],
          ),
        ),
        // 无译文时不留「英文 → 译文」的空隙；段间距在块尾无条件保留
        if (widget.translationMode != TranslationMode.hidden)
          const SizedBox(height: AppReading.enToTranslationGap),
        // 中文译文：4 模式
        switch (widget.translationMode) {
          TranslationMode.full => _TranslationText(
            text: widget.chineseTranslation,
            onTap: widget.onTranslationClick,
          ),
          TranslationMode.dim => Opacity(
            opacity: 0.55,
            child: _TranslationText(
              text: widget.chineseTranslation,
              onTap: widget.onTranslationClick,
            ),
          ),
          // 点击揭示：isRevealed 时显示明文，否则模糊（对照 Kotlin
          // ReadingScreen 的 BLURRED 分支 if (isRevealed) 拆解）
          TranslationMode.blurred => widget.isRevealed
              ? _TranslationText(
                  text: widget.chineseTranslation,
                  onTap: widget.onTranslationClick,
                )
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: _TranslationText(
                    text: widget.chineseTranslation,
                    onTap: widget.onTranslationClick,
                  ),
                ),
          TranslationMode.hidden => const SizedBox.shrink(),
        },
        // 段落间距算在本段块高内（块间无额外间距）——分页测量见 ArticlePaginator
        const SizedBox(height: AppReading.paragraphGap),
      ],
    );
  }

  /// 单词 → 可点击 TextSpan（生词珊瑚底色高亮）；空白/标点原样 TextSpan。
  /// 正在朗读的那一句（speakingSentenceIndex）文字追加同色底色，生词 span
  /// 保持原样（同色融合）；同一时刻只有一句带底色。
  List<InlineSpan> _buildAnnotatedSpans() {
    return buildWordSpans(
      text: widget.englishText,
      style: null,
      vocabularyWords: widget.vocabularyWords,
      recognizerFor: _wordRecognizer,
      speakingRange: _speakingRange(),
    );
  }

  /// 当前朗读句的字符区间（null = 本段未在朗读）。
  ///
  /// 无句级信息（系统 TTS 拼接朗读 / 首句上报前）时退化为整段高亮——与
  /// 句子级改造前的段落高亮行为一致。
  (int, int)? _speakingRange() {
    if (!widget.isSpeaking) return null;
    final index = widget.speakingSentenceIndex;
    if (index == null || index < 0 || index >= widget.sentences.length) {
      return (0, widget.englishText.length);
    }
    final sentence = widget.sentences[index];
    return (sentence.start, sentence.end);
  }
}

/// 译文文本（BLURRED 点击揭示 + DIM/FULL 可点击触发揭示回调）。
class _TranslationText extends StatelessWidget {
  const _TranslationText({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(text, style: AppType.readingTranslation),
    );
  }
}

/// 段尾内联播放按钮（18dp；朗读中显示 Stop + Primary，否则 VolumeUp + MutedSoft）。
class _InlinePlayButton extends StatelessWidget {
  const _InlinePlayButton({required this.isSpeaking, required this.onClick});

  final bool isSpeaking;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClick,
      child: Icon(
        isSpeaking ? Icons.stop_outlined : Icons.volume_up_outlined,
        size: 18,
        color: isSpeaking ? AppColors.primary : AppColors.mutedSoft,
      ),
    );
  }
}
