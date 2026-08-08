import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/components/app_button.dart';
import '../../core/components/app_modal.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'reading_controller.dart';
import 'translation_visibility.dart';
import 'word_extractor.dart';

/// Reading 页（对照 Kotlin ReadingScreen.kt）：
/// - 3dp 珊瑚滚动进度条（宽 = scrollFraction）
/// - ReadingAppBar：返回 + ✓已读 + 译文 label + 模式 chip（循环切换）
/// - 正文：标题 displayMedium serif + Hairline 分隔 + 段落
/// - 段落：18sp/30sp 行高、分词可点击（查词）、生词高亮
///   `background: Color(0x2ECC785C)`、段尾内联播放图标（18dp）、
///   译文 4 模式（FULL 显示 / DIM alpha 0.55 / BLURRED blur 4dp 点击揭示
///   + 10s 自动重新模糊 / HIDDEN 不渲染）
/// - 「标记已读」Secondary 全宽按钮（正文末尾，跟随滚动）
/// - 底部播放条（音乐播放器样式，常驻）：44dp 圆形 Primary 播放/停止 +
///   '朗读全文'/'正在朗读…' + 语速胶囊 1x/0.75x
/// - 查词弹窗（底部 AppModal）：词头 26sp serif + 36dp 发音钮 + 音标 +
///   按词性分组义项（词性标签珊瑚）+ '加入生词表'/'从生词表移除' 全宽按钮
/// - TTS 不可用：顶部 toast 4s + 拉起系统 TTS 设置（对照 Kotlin
///   LaunchedEffect(snackbarMessage/openTtsSettings)）
class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({
    super.key,
    required this.articleId,
    required this.onBack,
  });

  final int articleId;
  final VoidCallback onBack;

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollFraction = 0;
  Timer? _toastTimer;

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
    _toastTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readingControllerProvider(widget.articleId));

    // 副作用 1：TTS 不可用 toast 显示 4s 后自动清除
    ref.listen<String?>(
      readingControllerProvider(widget.articleId)
          .select((s) => s.snackbarMessage),
      (previous, next) {
        if (next == null) return;
        _toastTimer?.cancel();
        _toastTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            ref
                .read(readingControllerProvider(widget.articleId).notifier)
                .clearSnackbar();
          }
        });
      },
    );

    // 副作用 2：TTS 不可用时拉起系统 TTS 设置（替代 Kotlin
    // ACTION_CHECK_TTS_DATA Intent）
    ref.listen<bool>(
      readingControllerProvider(widget.articleId)
          .select((s) => s.openTtsSettings),
      (previous, next) {
        if (!next) return;
        final uri = Uri.parse('android.settings.TTS_SETTINGS');
        launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((_) => false);
      },
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      // SafeArea：灵动岛（挖孔）/手势条区域留安全边距（对照 Kotlin
      // enableEdgeToEdge + Scaffold 默认消费 systemBars insets）
      body: SafeArea(
        child: Stack(
          children: [
          Column(
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
                            isSpeaking:
                                state.speakingParagraphIndex == index,
                            onWordClick: (word) => ref
                                .read(readingControllerProvider(
                                        widget.articleId)
                                    .notifier)
                                .showWordSheet(word),
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
                                .read(readingControllerProvider(
                                        widget.articleId)
                                    .notifier)
                                .playParagraph(index),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        if (!state.isReadCompleted)
                          AppButton(
                            text: '标记已读',
                            onClick: () => ref
                                .read(readingControllerProvider(
                                        widget.articleId)
                                    .notifier)
                                .markAsRead(),
                            variant: AppButtonVariant.secondary,
                          ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                    ),
                },
              ),
              // 底部播放条：常驻（音乐播放器样式）
              _ReadingPlayerBar(
                isSpeaking: state.isSpeakingFullArticle,
                ttsSpeed: state.ttsSpeed,
                speechProgress: state.speechProgress,
                speechTotalParagraphs: state.speechTotalParagraphs,
                onTogglePlayback: () => ref
                    .read(readingControllerProvider(widget.articleId).notifier)
                    .toggleFullArticlePlayback(),
                onToggleTtsSpeed: () => ref
                    .read(readingControllerProvider(widget.articleId).notifier)
                    .toggleTtsSpeed(),
              ),
            ],
          ),
          // 顶部 TTS 不可用提示（对照 Kotlin SnackbarHost TopCenter）
          if (state.snackbarMessage != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: AppToast(state.snackbarMessage!),
              ),
            ),
          // 查词弹窗（底部全宽）
          AppModal(
            visible: state.isWordSheetVisible,
            onDismiss: () => ref
                .read(readingControllerProvider(widget.articleId).notifier)
                .hideWordSheet(),
            alignment: AppModalAlignment.bottom,
            child: _WordSheetBody(
              data: state.wordSheetData,
              onDismiss: () => ref
                  .read(readingControllerProvider(widget.articleId).notifier)
                  .hideWordSheet(),
              onPlayWord: () => ref
                  .read(readingControllerProvider(widget.articleId).notifier)
                  .playWordPronunciation(),
              onAddToVocabulary: () => ref
                  .read(readingControllerProvider(widget.articleId).notifier)
                  .addToVocabulary(),
              onRemoveFromVocabulary: () => ref
                  .read(readingControllerProvider(widget.articleId).notifier)
                  .removeFromVocabulary(),
            ),
          ),
        ],
        ),
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

/// 底部播放条：44dp 圆形播放/停止 + 状态文字 + 语速胶囊（对照 Kotlin
/// ReadingPlayerBar）。常驻于正文下方。
class _ReadingPlayerBar extends StatelessWidget {
  const _ReadingPlayerBar({
    required this.isSpeaking,
    required this.ttsSpeed,
    required this.speechProgress,
    required this.speechTotalParagraphs,
    required this.onTogglePlayback,
    required this.onToggleTtsSpeed,
  });

  final bool isSpeaking;
  final double ttsSpeed;
  final double? speechProgress;
  final int? speechTotalParagraphs;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleTtsSpeed;

  @override
  Widget build(BuildContext context) {
    final slow = ttsSpeed < 1.0;
    return Container(
      color: AppColors.surfaceCard,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          // 圆形播放/停止按钮
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                debugPrint('[UI] _ReadingPlayerBar onTap PLAY/STOP');
                onTogglePlayback();
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  isSpeaking ? Icons.stop : Icons.play_arrow,
                  color: AppColors.onPrimary,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (speechProgress != null && speechTotalParagraphs != null)
            Text(
              '生成中 ${speechProgress!.toStringAsFixed(0)}/${speechTotalParagraphs} 段',
              style: AppType.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            )
          else
            Text(
              isSpeaking ? '正在朗读…' : '朗读全文',
              style: AppType.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isSpeaking ? AppColors.primary : AppColors.bodyText,
              ),
            ),
          const Spacer(),
          // 语速胶囊（选中态 Primary 底 OnPrimary 文字）
          Material(
            color: slow ? AppColors.surfaceSoft : AppColors.primary,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onToggleTtsSpeed,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Text(
                  slow ? '0.75x' : '1x',
                  style: AppType.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: slow ? AppColors.mutedSoft : AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 查词弹窗内容（对照 Kotlin WordModalOverlay）：
/// 关闭 X → 词头 26sp serif + 发音钮 → 音标 → loading / 按词性分组义项 →
/// '加入生词表' / '从生词表移除' 全宽按钮。
class _WordSheetBody extends StatelessWidget {
  const _WordSheetBody({
    required this.data,
    required this.onDismiss,
    required this.onPlayWord,
    required this.onAddToVocabulary,
    required this.onRemoveFromVocabulary,
  });

  final WordSheetData? data;
  final VoidCallback onDismiss;
  final VoidCallback onPlayWord;
  final VoidCallback onAddToVocabulary;
  final VoidCallback onRemoveFromVocabulary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 关闭 X — 右上
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment.topRight,
            child: AppIconButton(
              icon: Icons.close,
              tooltip: '关闭',
              onClick: onDismiss,
              size: 32,
              tint: AppColors.mutedSoft,
            ),
          ),
        ),
        if (data != null) ...[
          // 词头 + 发音
          Row(
            children: [
              Text(
                data!.word,
                style: AppType.textTheme.headlineLarge
                    ?.copyWith(fontSize: 26),
              ),
              const Spacer(),
              if (!data!.isLoading)
                AppIconButton(
                  icon: Icons.volume_up_outlined,
                  tooltip: '发音',
                  onClick: onPlayWord,
                  size: 36,
                  tint: AppColors.primary,
                ),
            ],
          ),
          if (data!.phonetic != null && !data!.isLoading)
            Text(
              data!.phonetic!,
              style: AppType.phonetic.copyWith(fontSize: 13),
            ),
          if (data!.isLoading) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '正在查询…',
                  style: AppType.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ] else if (data!.senses.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            // 按词性分组：词性标签（珊瑚）只在组首出现
            for (final (index, sense) in data!.senses.indexed) ...[
              if (index == 0 ||
                  sense.partOfSpeech !=
                      data!.senses[index - 1].partOfSpeech) ...[
                const SizedBox(height: 16),
                Text(
                  sense.partOfSpeech,
                  style: AppType.textTheme.labelMedium
                      ?.copyWith(color: AppColors.primary),
                ),
                const SizedBox(height: 4),
              ] else ...[
                const SizedBox(height: 8),
              ],
              Text(
                sense.englishDefinition,
                style: AppType.textTheme.bodySmall
                    ?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                sense.chineseMeaning,
                style: AppType.textTheme.bodySmall
                    ?.copyWith(color: AppColors.mutedSoft),
              ),
            ],
          ],
          const SizedBox(height: 20),
          // 全宽操作按钮（已入生词本 → 移除，否则 → 加入）
          SizedBox(
            width: double.infinity,
            child: data!.isInVocabulary
                ? AppButton(
                    text: '从生词表移除',
                    onClick: onRemoveFromVocabulary,
                    variant: AppButtonVariant.secondary,
                  )
                : AppButton(
                    text: '加入生词表',
                    onClick: onAddToVocabulary,
                  ),
          ),
          const SizedBox(height: 4),
        ],
      ],
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
              // 点击揭示：isRevealed 时显示明文，否则模糊（对照 Kotlin
              // ReadingScreen 的 BLURRED 分支 if (isRevealed) 拆解）
              child: widget.isRevealed
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
