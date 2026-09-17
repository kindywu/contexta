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
import '../../core/layout/window_size.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../domain/tts/tts_engine.dart' show kTitleParagraphIndex;
import 'pagination/article_paginator.dart';
import 'pagination/reading_block.dart';
import 'pagination/spread_reader.dart';
import 'reading_controller.dart';
import 'reading_widgets.dart';
import 'translation_visibility.dart';

/// 分页引擎（无状态，全页面共用一个实例）。样式来自 `static final` 的
/// [AppType]，不能用于 `const` 构造，故提升到文件级。
final _paginator = ArticlePaginator(
  bodyStyle: AppType.readingBody,
  translationStyle: AppType.readingTranslation,
  titleStyle: AppType.readingTitle,
  buttonLabelStyle: AppType.textTheme.titleSmall!,
);

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

  /// 书页模式：当前跨页序号（页码展示 + 进度条取值）。
  final PageController _pageController = PageController();
  int _spreadIndex = 0;

  /// 分页结果按内容与尺寸 memo——句子高亮变化不改变文字度量，
  /// 命中缓存即不重排（否则朗读时每次句子切换都要重排全篇）。
  Object? _paginationKey;
  PaginatedArticle? _paginatedCache;

  /// 最近一次分页结果（朗读自动翻页按段落序号查页时用）。
  PaginatedArticle? get _lastPaginated => _paginatedCache;

  /// 进度条上一次构建时用的比例。分页发生在**布局阶段**（LayoutBuilder），
  /// 晚于进度条构建——分页算完后若比例变了要补一帧（见 [_buildSpread]），
  /// 否则首屏进度条停在 0、重排后停在旧值。
  double _barProgress = 0;

  /// 书页模式（expanded 档，宽 ≥ 840）：左右两页并排 + 整屏翻页。
  bool get _isSpreadMode => context.isExpandedLayout;

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
    _pageController.dispose();
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

    // 副作用 3：全文朗读句子切换 → 手机模式滚动到 1/3 处，书页模式翻到
    // 目标跨页（手滚 / 手翻跳过本次，下次切换恢复）
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
          if (_isSpreadMode) {
            if (_userScrolling) {
              _userScrolling = false; // 手翻跳过本次，下次切换恢复
              return;
            }
            turnToPageOfParagraph(paragraphIndex);
            return;
          }
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

    // 进度条取值：书页模式按跨页进度，手机模式按滚动比例（后者同原实现）；
    // 同时记下本次构建用的值，供 _buildSpread 判断分页后是否需要补一帧。
    final barProgress = _isSpreadMode ? _spreadProgress : _scrollFraction;
    _barProgress = barProgress;

    return Scaffold(
      backgroundColor: AppColors.background,
      // SafeArea：灵动岛（挖孔）/手势条区域留安全边距（对照 Kotlin
      // enableEdgeToEdge + Scaffold 默认消费 systemBars insets）
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 3dp 珊瑚进度条：书页模式取跨页进度，手机模式取滚动比例
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: MediaQuery.of(context).size.width * barProgress,
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
                      _isSpreadMode ? _buildSpread(state) : _buildList(state),
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

  /// 手机 / pad 竖屏路径：单列正文列表（书页模式接入前的原路径，未改动）。
  Widget _buildList(ReadingUiState state) {
    return NotificationListener<ScrollStartNotification>(
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
    );
  }

  /// 书页模式进度：已翻过的页占比（右页页号 / 总页数）。
  double get _spreadProgress {
    final total = _lastPaginated?.pages.length ?? 0;
    if (total == 0) return 0; // 首帧（尚未分页）不显示进度
    final right = ((_spreadIndex + 1) * 2).clamp(1, total);
    return right / total;
  }

  /// 供朗读自动翻页读取：目标段落所在页 → 跨页序号。
  void turnToPageOfParagraph(int paragraphIndex) {
    final paginated = _lastPaginated;
    if (paginated == null || !_pageController.hasClients) return;
    final page = paginated.pageOf(paragraphIndex);
    if (page == null) return;
    _pageController.animateToPage(
      page ~/ 2,
      duration: AppMotion.slow,
      curve: Curves.easeInOut,
    );
  }

  /// 书页模式（expanded 档）：按窗口尺寸分页后交给 [SpreadReader] 渲染。
  ///
  /// 分页只在「内容或尺寸变化」时重排（memo）：句子高亮、朗读态这类
  /// 高频状态变化不改变文字度量，必须命中缓存——否则每切一句都重排全篇。
  Widget _buildSpread(ReadingUiState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 跨页宽与 SpreadReader 同式（含最大宽限幅），页宽再扣中缝对半分
        final spreadWidth =
            (constraints.maxWidth - AppPage.horizontalPadding * 2).clamp(
              0.0,
              kSpreadMaxWidth,
            );
        final pageWidth = (spreadWidth - kSpreadGutter) / 2;
        // 页内容盒高 = 可用高 − 页码行 − 页内上下留白（与 SpreadReader 一致）
        final pageHeight =
            constraints.maxHeight -
            kPageIndicatorHeight -
            kPageTopPadding -
            kPageBottomPadding;
        // 英文正文/标题走 RichText（不吃 MediaQuery 字体缩放），译文与按钮
        // 文字走 Text（吃）——两个 scaler 各按自己的渲染器传
        final bodyTextScaler = TextScaler.noScaling;
        final labelTextScaler = MediaQuery.textScalerOf(context);
        final key = Object.hash(
          identityHashCode(state.paragraphs),
          state.title,
          state.translationMode,
          state.isReadCompleted,
          pageWidth,
          pageHeight,
          bodyTextScaler,
          labelTextScaler,
        );
        if (key != _paginationKey || _paginatedCache == null) {
          _paginationKey = key;
          _paginatedCache = _paginator.paginate(
            blocks: _buildBlocks(state),
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            bodyTextScaler: bodyTextScaler,
            labelTextScaler: labelTextScaler,
            translationMode: state.translationMode,
          );
          // 进度条在书页之前构建（本帧拿到分页结果时它已构建完）：比例变化
          // 后补一帧，让首屏进度条立即显示当前跨页占比。分页只在内容/尺寸
          // 变化时重排，补帧不常发生，且补帧后 memo 命中不会连锁触发。
          if (_spreadProgress != _barProgress) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        }
        final paginated = _paginatedCache!;
        return SpreadReader(
          paginated: paginated,
          pageController: _pageController,
          title: state.title ?? '文章',
          paragraphs: state.paragraphs,
          sentencesByParagraph: state.sentencesByParagraph,
          translationMode: state.translationMode,
          revealedParagraphs: state.revealedParagraphs,
          vocabularyWords: state.vocabularyWords,
          speakingParagraphIndex: state.speakingParagraphIndex,
          speakingSentenceIndex: state.speakingSentenceIndex,
          paragraphKey: _paragraphKey,
          paragraphTextKey: _paragraphTextKey,
          onWordClick: (word) => ref
              .read(readingControllerProvider(widget.articleId).notifier)
              .showWordSheet(word),
          onTranslationClick: (index) {
            if (state.translationMode == TranslationMode.blurred) {
              ref
                  .read(readingControllerProvider(widget.articleId).notifier)
                  .revealTranslation(index);
            }
          },
          onPlayParagraph: (index) => ref
              .read(readingControllerProvider(widget.articleId).notifier)
              .playParagraph(index),
          onMarkAsRead: () => ref
              .read(readingControllerProvider(widget.articleId).notifier)
              .markAsRead(),
          onSpreadChanged: (index) => setState(() => _spreadIndex = index),
          onUserDrag: () => _userScrolling = true,
        );
      },
    );
  }

  /// 书页分页的块序列：标题 + 各段 + （未读时）标记已读按钮。
  List<ReadingBlock> _buildBlocks(ReadingUiState state) => [
    TitleBlock(state.title ?? '文章'),
    for (final (index, paragraph) in state.paragraphs.indexed)
      ParagraphBlock(
        index: index,
        englishText: paragraph.englishText,
        chineseTranslation: paragraph.chineseTranslation,
      ),
    if (!state.isReadCompleted) const MarkAsReadBlock(),
  ];
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
