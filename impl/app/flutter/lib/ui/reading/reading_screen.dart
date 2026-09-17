import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/components/app_button.dart';
import '../../core/components/app_modal.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../domain/tts/tts_engine.dart' show kTitleParagraphIndex;
import 'reading_controller.dart';
import 'reading_widgets.dart';
import 'translation_visibility.dart';

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

  /// 用户手指拖拽中（暂停自动跟随；程序滚动 animateTo 不触发）。
  bool _userScrolling = false;

  /// 每段一个缓存的 GlobalObjectKey。GlobalObjectKey 按 identical 判等，
  /// 查找必须复用创建时的同一实例（每次新建等值 String 无法命中），
  /// 因此按 index 缓存，build 与 _scrollToParagraph 共用。
  final Map<int, GlobalObjectKey<State<StatefulWidget>>> _paragraphKeys = {};
  GlobalObjectKey<State<StatefulWidget>> _paragraphKey(int index) =>
      _paragraphKeys.putIfAbsent(
        index,
        () => GlobalObjectKey('reading-para-$index'),
      );

  /// 段落英文正文 RichText 的 key（按句滚动要取文字盒坐标）。
  final Map<int, GlobalObjectKey<State<StatefulWidget>>> _paragraphTextKeys = {};
  GlobalObjectKey<State<StatefulWidget>> _paragraphTextKey(int index) =>
      _paragraphTextKeys.putIfAbsent(
        index,
        () => GlobalObjectKey('reading-para-text-$index'),
      );

  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    // 阅读页期间屏幕常亮：阻止系统休眠/自动变暗（阅读类 app 标准行为；
    // 离开页面（dispose）时关闭）。后台时 Android 系统自动失效，无需处理。
    WakelockPlus.enable();
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
    WakelockPlus.disable();
    _toastTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动使当前朗读句顶部对齐视口 1/3 处（getOffsetToReveal + animateTo
  /// 300ms easeInOut）。用户手指拖拽中跳过本次，下次句子切换恢复跟随。
  ///
  /// 句子不是独立 render object（同一段是单个 RichText），故在段落定位偏移
  /// 之上叠加句首盒子在段落内的 y 偏移（[RenderParagraph.getBoxesForSelection]）。
  /// 拿不到盒子（未构建 / 空区间）时退化为段落级对齐——句子就在该段内，
  /// 目视仍可见。
  void _scrollToSentence(int index, ArticleSentence sentence, int total) {
    if (_userScrolling) {
      _userScrolling = false; // 手滚跳过本次，下次句子切换恢复
      return;
    }
    final renderObj = _paragraphKey(index).currentContext?.findRenderObject();
    if (renderObj == null) {
      // 段落未构建（超出 viewport + cacheExtent，如大幅跳转后）：估算定位兜底。
      // 近似滚到 index/total 处即可——段内即构建，下一次切换会精确对齐。
      if (!_scrollController.hasClients || total <= 0) return;
      final estimated =
          _scrollController.position.maxScrollExtent * index / total;
      _scrollController.animateTo(
        estimated,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }
    if (!_scrollController.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(renderObj);
    if (viewport == null) return;
    var offset = viewport.getOffsetToReveal(renderObj, 1 / 3).offset;
    offset += _sentenceTopInParagraph(index, sentence) ?? 0;
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 句首行相对**本段首行**的 y 偏移（0 = 与该段首行同行，即段落顶部对齐
  /// 无需额外偏移）；取不到返回 null。
  ///
  /// 用「减首行盒顶」而非绝对盒顶：文字盒默认按 tight 高度测量，盒顶比行盒
  /// 顶低数像素（行高带来的 leading），做差可抵消该常量，得到真实的换行偏移。
  double? _sentenceTopInParagraph(int index, ArticleSentence sentence) {
    final renderObj =
        _paragraphTextKey(index).currentContext?.findRenderObject();
    if (renderObj is! RenderParagraph) return null;
    final firstBoxes = renderObj.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    final boxes = renderObj.getBoxesForSelection(
      TextSelection(baseOffset: sentence.start, extentOffset: sentence.end),
    );
    if (boxes.isEmpty || firstBoxes.isEmpty) return null;
    return boxes.first.top - firstBoxes.first.top;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readingControllerProvider(widget.articleId));

    // 副作用 1：TTS 不可用 toast 显示 4s 后自动清除
    ref.listen<String?>(
      readingControllerProvider(
        widget.articleId,
      ).select((s) => s.snackbarMessage),
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
      readingControllerProvider(
        widget.articleId,
      ).select((s) => s.openTtsSettings),
      (previous, next) {
        if (!next) return;
        final uri = Uri.parse('android.settings.TTS_SETTINGS');
        launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
      },
    );

    // 副作用 3：全文朗读句子切换 → 自动滚动到 1/3 处
    ref.listen<(int?, int?)>(
      readingControllerProvider(widget.articleId)
          .select((s) => (s.speakingParagraphIndex, s.speakingSentenceIndex)),
      (previous, next) {
        final (paragraphIndex, sentenceIndex) = next;
        if (paragraphIndex == null || paragraphIndex < 0) {
          return; // 标题段（-1）不滚动
        }
        if (sentenceIndex == null) return;
        final state = ref.read(readingControllerProvider(widget.articleId));
        if (!state.isSpeakingFullArticle) return; // 单段播放只高亮不滚动
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final sentences = paragraphIndex < state.sentencesByParagraph.length
              ? state.sentencesByParagraph[paragraphIndex]
              : const <ArticleSentence>[];
          if (sentenceIndex < 0 || sentenceIndex >= sentences.length) return;
          _scrollToSentence(
            paragraphIndex,
            sentences[sentenceIndex],
            state.paragraphs.length,
          );
        });
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
                  onCycleTranslationMode: () => ref
                      .read(
                        readingControllerProvider(widget.articleId).notifier,
                      )
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
                    (false, null) =>
                      NotificationListener<ScrollStartNotification>(
                        onNotification: (notification) {
                          if (notification.dragDetails != null) {
                            _userScrolling = true;
                          }
                          return false;
                        },
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppPage.horizontalPadding,
                          ),
                          children: [
                            const SizedBox(height: AppSpacing.sm),
                            ReadingTitle(
                              text: state.title ?? '文章',
                              isSpeaking:
                                  state.speakingParagraphIndex ==
                                  kTitleParagraphIndex,
                              vocabularyWords: state.vocabularyWords,
                              onWordClick: (word) => ref
                                  .read(
                                    readingControllerProvider(
                                      widget.articleId,
                                    ).notifier,
                                  )
                                  .showWordSheet(word),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Container(height: 1, color: AppColors.hairline),
                            const SizedBox(height: AppSpacing.lg),
                            for (final (index, paragraph)
                                in state.paragraphs.indexed)
                              ReadingParagraph(
                                key: _paragraphKey(index),
                                textKey: _paragraphTextKey(index),
                                englishText: paragraph.englishText,
                                chineseTranslation:
                                    paragraph.chineseTranslation,
                                sentences: index <
                                        state.sentencesByParagraph.length
                                    ? state.sentencesByParagraph[index]
                                    : const [],
                                speakingSentenceIndex:
                                    state.speakingParagraphIndex == index
                                        ? state.speakingSentenceIndex
                                        : null,
                                translationMode: state.translationMode,
                                isRevealed: state.revealedParagraphs.contains(
                                  index,
                                ),
                                vocabularyWords: state.vocabularyWords,
                                isSpeaking:
                                    state.speakingParagraphIndex == index,
                                onWordClick: (word) => ref
                                    .read(
                                      readingControllerProvider(
                                        widget.articleId,
                                      ).notifier,
                                    )
                                    .showWordSheet(word),
                                onTranslationClick: () {
                                  if (state.translationMode ==
                                      TranslationMode.blurred) {
                                    ref
                                        .read(
                                          readingControllerProvider(
                                            widget.articleId,
                                          ).notifier,
                                        )
                                        .revealTranslation(index);
                                  }
                                },
                                onPlay: () => ref
                                    .read(
                                      readingControllerProvider(
                                        widget.articleId,
                                      ).notifier,
                                    )
                                    .playParagraph(index),
                              ),
                            const SizedBox(height: AppSpacing.lg),
                            if (!state.isReadCompleted)
                              AppButton(
                                text: '标记已读',
                                onClick: () => ref
                                    .read(
                                      readingControllerProvider(
                                        widget.articleId,
                                      ).notifier,
                                    )
                                    .markAsRead(),
                                variant: AppButtonVariant.secondary,
                              ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                        ),
                      ),
                  },
                ),
                // 底部播放条：常驻（音乐播放器样式）
                _ReadingPlayerBar(
                  isSpeaking: state.isSpeakingFullArticle,
                  ttsSpeed: state.ttsSpeed,
                  speechProgress: state.speechProgress,
                  speechTotalSentences: state.speechTotalSentences,
                  onTogglePlayback: () => ref
                      .read(
                        readingControllerProvider(widget.articleId).notifier,
                      )
                      .toggleFullArticlePlayback(),
                  onToggleTtsSpeed: () => ref
                      .read(
                        readingControllerProvider(widget.articleId).notifier,
                      )
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
                child: Center(child: AppToast(state.snackbarMessage!)),
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
              style: AppType.textTheme.labelMedium?.copyWith(
                color: AppColors.mutedSoft,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '译文',
            style: AppType.textTheme.labelMedium?.copyWith(
              color: AppColors.mutedSoft,
            ),
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
                    style: AppType.textTheme.labelMedium?.copyWith(
                      color: AppColors.bodyText,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    '▾',
                    style: AppType.textTheme.labelSmall?.copyWith(
                      color: AppColors.mutedSoft,
                    ),
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
    required this.speechTotalSentences,
    required this.onTogglePlayback,
    required this.onToggleTtsSpeed,
  });

  final bool isSpeaking;
  final double ttsSpeed;
  final double? speechProgress;
  final int? speechTotalSentences;
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
          if (speechProgress != null && speechTotalSentences != null)
            Text(
              '第 ${speechProgress!.toStringAsFixed(0)}/$speechTotalSentences 句',
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  _speedLabel(ttsSpeed),
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

  /// 语速显示标签：0.8x / 1x / 1.2x（去掉多余的小数位）。
  String _speedLabel(double speed) {
    if (speed == 0.8) return '0.8x';
    if (speed == 1.2) return '1.2x';
    return '1x';
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
    // 关闭 X 固定置顶（不随内容滚动）；义项/按钮区包可滚动容器——
    // 内容总高超过 AppModal 的 85% 屏高上限（底部弹层）时可滚动查看。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 关闭 X — 右上（固定头部，不随滚动）
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
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data != null) ...[
                  // 词头 + 发音
                  Row(
                    children: [
                      Text(
                        data!.word,
                        style: AppType.textTheme.headlineLarge?.copyWith(
                          fontSize: 26,
                        ),
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
                  // 词形解析标注：homes 是 home 的复数形式
                  if (data!.inflectionNote != null && !data!.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        data!.inflectionNote!,
                        style: AppType.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
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
                          style: AppType.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
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
                          style: AppType.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ] else ...[
                        const SizedBox(height: 8),
                      ],
                      Text(
                        sense.englishDefinition,
                        style: AppType.textTheme.bodySmall?.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sense.chineseMeaning,
                        style: AppType.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedSoft,
                        ),
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
                        : AppButton(text: '加入生词表', onClick: onAddToVocabulary),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
