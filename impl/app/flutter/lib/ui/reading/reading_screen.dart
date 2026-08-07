import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_button.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'reading_controller.dart';
import 'translation_visibility.dart';
import 'word_extractor.dart';

/// Reading 页（对照 Kotlin ReadingScreen.kt 的正文部分；Task 24 扩展
/// 播放条 + 查词弹窗）：
/// - 3dp 珊瑚滚动进度条（宽 = scrollFraction）
/// - ReadingAppBar：返回 + ✓已读 + 译文 label + 模式 chip（循环切换）
/// - 正文：标题 displayMedium serif + Hairline 分隔 + 段落
/// - 段落：18sp/30sp 行高、分词可点击（查词回调）、生词高亮
///   `background: Color(0x2ECC785C)`、段尾内联播放图标（18dp）、
///   译文 4 模式（FULL 显示 / DIM alpha 0.55 / BLURRED blur 4dp 点击揭示
///   + 10s 自动重新模糊 / HIDDEN 不渲染）
/// - 「标记已读」Secondary 全宽按钮（正文末尾，跟随滚动）
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({
    super.key,
    required this.articleId,
    required this.onBack,
    required this.onWordClick,
  });

  final int articleId;
  final VoidCallback onBack;

  /// 点击正文单词 → 查词（Task 24 实现弹窗）。
  final ValueChanged<String> onWordClick;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollFraction = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final max = _scrollController.position.maxScrollExtent;
      final fraction = max > 0
          ? (_scrollController.offset / max).clamp(0.0, 1.0)
          : 0.0;
      if ((fraction - _scrollFraction).abs() > 0.001) {
        setState(() => _scrollFraction = fraction);
      }
    });
    // 对照 Kotlin LaunchedEffect(articleId)：进入页面即加载
    Future.microtask(() {
      ref
          .read(readingControllerProvider(widget.articleId).notifier)
          .loadArticle(widget.articleId);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readingControllerProvider(widget.articleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 3dp 珊瑚滚动进度条（宽 = 滚动比例）
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: MediaQuery.of(context).size.width * _scrollFraction,
              height: 3,
              color: AppColors.primary,
            ),
          ),
          _ReadingAppBar(
            translationMode: state.translationMode,
            isReadCompleted: state.isReadCompleted,
            onBack: widget.onBack,
            onCycleTranslationMode: () =>
                ref.read(readingControllerProvider(widget.articleId).notifier)
                    .cycleTranslationMode(),
          ),
          Expanded(
            child: switch ((state.isLoading, state.error)) {
              (true, _) => const LoadingIndicator(),
              (false, final String error) => EmptyState(
                  icon: Icons.error_outline,
                  message: error,
                  subMessage: '请返回重新选择',
                ),
              (false, null) => ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppPage.horizontalPadding),
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      state.title ?? '文章',
                      style: AppType.textTheme.displayMedium
                          ?.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(height: 1, color: AppColors.hairline),
                    const SizedBox(height: AppSpacing.lg),
                    for (final (index, paragraph)
                        in state.paragraphs.indexed)
                      _ReadingParagraph(
                        key: ValueKey(index),
                        englishText: paragraph.englishText,
                        chineseTranslation: paragraph.chineseTranslation,
                        translationMode: state.translationMode,
                        isRevealed:
                            state.revealedParagraphs.contains(index),
                        vocabularyWords: state.vocabularyWords,
                        isSpeaking: state.speakingParagraphIndex == index,
                        onWordClick: widget.onWordClick,
                        onTranslationClick: () {
                          if (state.translationMode ==
                              TranslationMode.blurred) {
                            ref
                                .read(readingControllerProvider(
                                        widget.articleId)
                                    .notifier)
                                .revealTranslation(index);
                          }
                        },
                        onPlay: () => ref
                            .read(readingControllerProvider(widget.articleId)
                                .notifier)
                            .playParagraph(index),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    if (!state.isReadCompleted)
                      AppButton(
                        text: '标记已读',
                        onClick: () => ref
                            .read(readingControllerProvider(widget.articleId)
                                .notifier)
                            .markAsRead(),
                        variant: AppButtonVariant.secondary,
                      ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ),
            },
          ),
        ],
      ),
    );
  }
}

/// 阅读页顶栏：返回 + ✓已读 + 译文模式 chip（对照 Kotlin ReadingAppBar）。
class _ReadingAppBar extends StatelessWidget {
  const _ReadingAppBar({
    required this.translationMode,
    required this.isReadCompleted,
    required this.onBack,
    required this.onCycleTranslationMode,
  });

  final TranslationMode translationMode;
  final bool isReadCompleted;
  final VoidCallback onBack;
  final VoidCallback onCycleTranslationMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back,
            tooltip: '返回',
            onClick: onBack,
            tint: AppColors.mutedSoft,
          ),
          if (isReadCompleted) ...[
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '✓ 已读',
              style: AppType.textTheme.labelMedium
                  ?.copyWith(color: AppColors.mutedSoft),
            ),
          ],
          const Spacer(),
          Text(
            '译文',
            style: AppType.textTheme.labelMedium
                ?.copyWith(color: AppColors.mutedSoft),
          ),
          const SizedBox(width: AppSpacing.xs),
          InkWell(
            onTap: onCycleTranslationMode,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Text(
                    translationMode.label,
                    style: AppType.textTheme.labelMedium
                        ?.copyWith(color: AppColors.bodyText),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    '▾',
                    style: AppType.textTheme.labelSmall
                        ?.copyWith(color: AppColors.mutedSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个段落：可点击分词 + 内联播放图标 + 译文（对照 Kotlin ReadingParagraph）。
/// StatefulWidget 持有分词 TapGestureRecognizer，dispose 时统一释放。
class _ReadingParagraph extends StatefulWidget {
  const _ReadingParagraph({
    super.key,
    required this.englishText,
    required this.chineseTranslation,
    required this.translationMode,
    required this.isRevealed,
    required this.vocabularyWords,
    required this.isSpeaking,
    required this.onWordClick,
    required this.onTranslationClick,
    required this.onPlay,
  });

  final String englishText;
  final String chineseTranslation;
  final TranslationMode translationMode;
  final bool isRevealed;
  final Set<String> vocabularyWords;
  final bool isSpeaking;
  final ValueChanged<String> onWordClick;
  final VoidCallback onTranslationClick;
  final VoidCallback onPlay;

  @override
  State<_ReadingParagraph> createState() => _ReadingParagraphState();
}

class _ReadingParagraphState extends State<_ReadingParagraph> {
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
          text: TextSpan(
            style: AppType.textTheme.bodyLarge?.copyWith(
              color: AppColors.ink,
              fontSize: 18,
              height: 30 / 18,
            ),
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
        const SizedBox(height: 4),
        // 中文译文：4 模式
        switch (widget.translationMode) {
          TranslationMode.full => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _TranslationText(
                text: widget.chineseTranslation,
                onTap: widget.onTranslationClick,
              ),
            ),
          TranslationMode.dim => Opacity(
              opacity: 0.55,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _TranslationText(
                  text: widget.chineseTranslation,
                  onTap: widget.onTranslationClick,
                ),
              ),
            ),
          TranslationMode.blurred => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: _TranslationText(
                  text: widget.chineseTranslation,
                  onTap: widget.onTranslationClick,
                ),
              ),
            ),
          TranslationMode.hidden => const SizedBox.shrink(),
        },
      ],
    );
  }

  /// 单词 → 可点击 TextSpan（生词珊瑚底色高亮）；空白/标点原样 TextSpan。
  List<InlineSpan> _buildAnnotatedSpans() {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in findWordRanges(widget.englishText)) {
      final gap = widget.englishText.substring(cursor, range.$1);
      if (gap.isNotEmpty) {
        spans.add(TextSpan(text: gap));
      }
      final word = widget.englishText.substring(range.$1, range.$2);
      final normalized = word.toLowerCase();
      final isVocab = widget.vocabularyWords.contains(normalized);
      spans.add(
        TextSpan(
          text: word,
          style: isVocab
              ? const TextStyle(
                  color: AppColors.ink,
                  backgroundColor: Color(0x2ECC785C),
                )
              : const TextStyle(color: AppColors.ink),
          recognizer: _wordRecognizer(normalized),
        ),
      );
      cursor = range.$2;
    }
    final tail = widget.englishText.substring(cursor);
    if (tail.isNotEmpty) {
      spans.add(TextSpan(text: tail));
    }
    return spans;
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
      child: Text(
        text,
        style: AppType.textTheme.bodyMedium
            ?.copyWith(color: AppColors.mutedSoft),
      ),
    );
  }
}

/// 段尾内联播放按钮（18dp；朗读中显示 Stop + Primary，否则 VolumeUp + MutedSoft）。
class _InlinePlayButton extends StatelessWidget {
  const _InlinePlayButton({
    required this.isSpeaking,
    required this.onClick,
  });

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
