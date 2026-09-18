import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/components/app_modal.dart';
import '../core/components/loading_indicator.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../ui/reading/reading_controller.dart';
import '../ui/reading/reading_chrome.dart';
import '../ui/reading/translation_visibility.dart';
import 'pad_layout.dart';
import 'reading/article_paginator.dart';
import 'reading/pad_paginator_factory.dart';
import 'reading/pad_reading_chrome.dart';
import 'reading/pad_spread_reader.dart';
import 'reading/reading_block.dart';

/// Pad 阅读页：**沉浸式书页**（整屏左右两屏 + 按需唤出的工具栏）。
///
/// 与手机阅读页（单列无限滚动）是两棵独立的界面树，互不影响——本页只在
/// pad 界面树里被路由使用（见 `core/navigation/pad_router` 一路的分叉点）。
///
/// **默认几乎什么都不画**：书页占满整屏，底部只留一条胶囊带、左上角一个圆形
/// 返回键。点胶囊唤出顶栏（返回 / 标题 / 译文）与底栏（进度 / 朗读 / 语速）；
/// 上下栏以覆盖层滑入，**不推挤书页**——否则每次唤出控件文字都要重排一次，
/// 翻页时会看到内容跳。
///
/// 竖直方向的空间账：改造前常驻顶栏 + 常驻播放条吃掉约 110dp，正文每页因此
/// 少放 3~4 行；现在全部还给正文，只保留 [PadLayout.pagePillRowHeight] 一条
/// 胶囊带。
///
/// 两条常驻件是 2026-09-18 实测补的——此前的"绝对沉浸"把**出口**和**朗读**
/// 都藏进了唤出态，读者找不到：返回键只在顶栏里，朗读只在底栏里。现在
/// 左上角常驻返回键（唤出时让位给顶栏那个，不重复），胶囊旁常驻「朗读全文」。
///
/// 数据与朗读复用同一套 `readingControllerProvider`：沉浸只改变"控件什么时候
/// 出现"，不改变"文章怎么加载、怎么朗读、怎么查词"。
class PadReadingScreen extends ConsumerStatefulWidget {
  const PadReadingScreen({
    super.key,
    required this.articleId,
    required this.onBack,
  });

  final int articleId;
  final VoidCallback onBack;

  @override
  ConsumerState<PadReadingScreen> createState() => _PadReadingScreenState();
}

class _PadReadingScreenState extends ConsumerState<PadReadingScreen> {
  final PageController _pageController = PageController();
  final List<GlobalObjectKey> _paragraphKeys = [];
  final List<GlobalObjectKey> _paragraphTextKeys = [];

  /// 工具栏是否唤出。默认收起 —— 这是本次沉浸式重设计的核心开关。
  bool _chromeVisible = false;

  /// 当前跨页序号（页码与进度条取值）。
  int _spreadIndex = 0;

  /// 分页结果按内容与尺寸 memo——句子高亮变化不改变文字度量，命中缓存即不
  /// 重排（否则朗读时每次句子切换都要重排全篇）。
  Object? _paginationKey;
  PaginatedArticle? _paginatedCache;

  /// 非 null = 整篇只占一页，改排**单栏居中**（宽度即此值）。
  /// 见 [PadLayout.singleColumnMaxWidth]——避免短文在宽屏上右半屏留白。
  double? _singlePageWidth;

  /// 读者刚手动翻页 → 跳过一次朗读自动翻页。
  bool _userTurned = false;

  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _pageController.addListener(_onPageChanged);
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
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    final page = _pageController.page?.round() ?? 0;
    if (page != _spreadIndex) {
      setState(() => _spreadIndex = page);
    }
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _hideChrome() {
    if (_chromeVisible) setState(() => _chromeVisible = false);
  }

  /// 段落 key 按 index 缓存实例：GlobalObjectKey 按 `identical(value)` 判等，
  /// 每次新建插值字符串永远无法命中（与手机阅读页同款约定）。
  GlobalObjectKey _paragraphKey(int index) {
    while (_paragraphKeys.length <= index) {
      _paragraphKeys.add(
        GlobalObjectKey('reading-para-${_paragraphKeys.length}'),
      );
    }
    return _paragraphKeys[index];
  }

  GlobalObjectKey _paragraphTextKey(int index) {
    while (_paragraphTextKeys.length <= index) {
      _paragraphTextKeys.add(
        GlobalObjectKey('reading-para-text-${_paragraphTextKeys.length}'),
      );
    }
    return _paragraphTextKeys[index];
  }

  /// 书页模式进度：已翻过的页占比（右页页号 / 总页数）。
  double get _spreadProgress {
    final total = _paginatedCache?.pages.length ?? 0;
    if (total == 0) return 0;
    final right = ((_spreadIndex + 1) * 2).clamp(1, total);
    return right / total;
  }

  /// 朗读跟随：句子所在段落 → 页 → 跨页（纯查表，不二次测量）。
  void _turnToPageOfParagraph(int paragraphIndex) {
    final paginated = _paginatedCache;
    if (paginated == null || !_pageController.hasClients) return;
    final page = paginated.pageOf(paragraphIndex);
    if (page == null) return;
    _pageController.animateToPage(
      page ~/ 2,
      duration: AppMotion.slow,
      curve: Curves.easeInOut,
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readingControllerProvider(widget.articleId));
    final notifier = ref.read(
      readingControllerProvider(widget.articleId).notifier,
    );

    // TTS 不可用 toast 显示 4s 后自动清除
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

    // TTS 不可用时拉起系统 TTS 设置
    ref.listen<bool>(
      readingControllerProvider(
        widget.articleId,
      ).select((s) => s.openTtsSettings),
      (previous, next) {
        if (!next) return;
        launchUrl(
          Uri.parse('android.settings.TTS_SETTINGS'),
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
      },
    );

    // 全文朗读句子切换 → 跨页则自动翻页（沉浸态下也照样跟随）
    ref.listen<(int?, int?)>(
      readingControllerProvider(
        widget.articleId,
      ).select((s) => (s.speakingParagraphIndex, s.speakingSentenceIndex)),
      (previous, next) {
        final (paragraphIndex, _) = next;
        if (paragraphIndex == null || paragraphIndex < 0) return;
        final current = ref.read(readingControllerProvider(widget.articleId));
        if (!current.isSpeakingFullArticle) return; // 单段播放只高亮不翻页
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_userTurned) {
            _userTurned = false; // 手翻跳过本次，下次切换恢复跟随
            return;
          }
          _turnToPageOfParagraph(paragraphIndex);
        });
      },
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // 书页：占满整屏（底部留给页码胶囊一条带）
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: PadLayout.pagePillRowHeight,
                ),
                child: switch ((state.isLoading, state.error)) {
                  (true, _) => const LoadingIndicator(),
                  (false, final String error) => EmptyState(
                    icon: Icons.error_outline,
                    message: error,
                    subMessage: '请返回重新选择',
                  ),
                  (false, null) => _buildSpread(state, notifier),
                },
              ),
            ),

            // 空态 / 错误态下不显示任何控件：没有书页可翻，胶囊只会误导
            if (state.error == null && !state.isLoading) ...[
              // 页码胶囊（收起态常驻）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: PadLayout.pagePillRowHeight,
                child: IgnorePointer(
                  ignoring: _chromeVisible,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 0 : 1,
                    duration: AppMotion.base,
                    child: Center(
                      child: _paginatedCache == null
                          ? const SizedBox.shrink()
                          : PadPagePill(
                              pageController: _pageController,
                              totalPages: _paginatedCache!.pages.length,
                              isSpeaking: state.isSpeakingFullArticle,
                              onToggleChrome: _toggleChrome,
                              onTogglePlayback:
                                  notifier.toggleFullArticlePlayback,
                            ),
                    ),
                  ),
                ),
              ),

              // 左上角常驻返回键（唤出态淡出，位置让给顶栏里的那个）
              Positioned(
                left: AppSpacing.xxs,
                top: AppSpacing.xxs,
                child: IgnorePointer(
                  ignoring: _chromeVisible,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible ? 0 : 1,
                    duration: AppMotion.base,
                    child: PadReadingFloatingBack(onBack: widget.onBack),
                  ),
                ),
              ),

              // 唤出态顶栏（覆盖层滑入，不推挤书页）
              _ChromeSlot(
                visible: _chromeVisible,
                alignment: Alignment.topCenter,
                hiddenOffset: const Offset(0, -1),
                child: PadReadingTopBar(
                  title: state.title ?? '文章',
                  translationMode: state.translationMode,
                  isReadCompleted: state.isReadCompleted,
                  onBack: widget.onBack,
                  onCycleTranslationMode: notifier.cycleTranslationMode,
                ),
              ),

              // 唤出态底栏
              _ChromeSlot(
                visible: _chromeVisible,
                alignment: Alignment.bottomCenter,
                hiddenOffset: const Offset(0, 1),
                child: PadReadingBottomBar(
                  progress: _spreadProgress,
                  pageLabel: _pageLabel(),
                  isSpeaking: state.isSpeakingFullArticle,
                  ttsSpeed: state.ttsSpeed,
                  speechProgress: state.speechProgress,
                  speechTotalSentences: state.speechTotalSentences,
                  onTogglePlayback: notifier.toggleFullArticlePlayback,
                  onToggleTtsSpeed: notifier.toggleTtsSpeed,
                  onCollapse: _hideChrome,
                ),
              ),

              // 工具栏开着时，点书页空白处收起（点单词仍然查词——
              // 更深的单词 recognizer 在手势竞技场里先胜出）
              if (_chromeVisible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hideChrome,
                  ),
                ),
            ],

            if (state.snackbarMessage != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 0,
                right: 0,
                child: Center(child: AppToast(state.snackbarMessage!)),
              ),

            // 查词面板：pad 上居中限宽的底部弹层（宽屏贴边全宽很难读）
            AppModal(
              visible: state.isWordSheetVisible,
              onDismiss: notifier.hideWordSheet,
              alignment: AppModalAlignment.bottom,
              child: WordSheetBody(
                data: state.wordSheetData,
                onDismiss: notifier.hideWordSheet,
                onPlayWord: notifier.playWordPronunciation,
                onAddToVocabulary: notifier.addToVocabulary,
                onRemoveFromVocabulary: notifier.removeFromVocabulary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _pageLabel() {
    final total = _paginatedCache?.pages.length ?? 0;
    final right = ((_spreadIndex + 1) * 2).clamp(total == 0 ? 0 : 1, total);
    return '$right / $total 页';
  }

  Widget _buildSpread(ReadingUiState state, ReadingController notifier) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 全部尺寸来自约束：书页内容区 = 可用宽 − 页边距，上限 spreadMaxWidth
        // （保证单页正文不超过可读行宽）；页高 = 可用高 − 页内留白。
        final spreadWidth =
            (constraints.maxWidth - PadLayout.pagePadding * 2).clamp(
              0.0,
              PadLayout.spreadMaxWidth,
            );
        final pageWidth = (spreadWidth - kSpreadGutter) / 2;
        final pageHeight =
            constraints.maxHeight - kPageTopPadding - kPageBottomPadding;

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
          final wasUnpaginated = _paginatedCache == null;
          _paginationKey = key;
          final paginator = buildPadPaginator(
            DefaultTextStyle.of(context).style,
          );
          final blocks = _buildBlocks(state);
          _paginatedCache = paginator.paginate(
            blocks: blocks,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            bodyTextScaler: bodyTextScaler,
            labelTextScaler: labelTextScaler,
            translationMode: state.translationMode,
          );
          // 整篇一页放得下 → 书页范式退化成"左页有字 + 右半屏死区"，
          // 改按单栏宽**重新分页**（不是直接拉宽渲染：那样测量与渲染不同源，
          // 正是本文件踩过的坑）。更宽只会放得更下，故结果必然仍是 1 页。
          _singlePageWidth = null;
          if (_paginatedCache!.pages.length == 1) {
            final single = spreadWidth.clamp(0.0, PadLayout.singleColumnMaxWidth);
            if (single > pageWidth) {
              final repaginated = paginator.paginate(
                blocks: blocks,
                pageWidth: single,
                pageHeight: pageHeight,
                bodyTextScaler: bodyTextScaler,
                labelTextScaler: labelTextScaler,
                translationMode: state.translationMode,
              );
              if (repaginated.pages.length == 1) {
                _paginatedCache = repaginated;
                _singlePageWidth = single;
              }
            }
          }
          // 首次分页发生在 **layout 阶段**（本方法由 LayoutBuilder 调用），而
          // 页码胶囊是 Stack 里的兄弟节点，它的 build 早就跑完了——那一次它
          // 读到的是 `_paginatedCache == null`，渲染成占位空盒。不补这一帧，
          // 胶囊会永远停在空盒上（书页正常，只有胶囊永远不出现）。
          if (wasUnpaginated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
        }

        return PadSpreadReader(
          paginated: _paginatedCache!,
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
          onWordClick: notifier.showWordSheet,
          onTranslationClick: (index) {
            if (state.translationMode == TranslationMode.blurred) {
              notifier.revealTranslation(index);
            }
          },
          onPlayParagraph: notifier.playParagraph,
          onMarkAsRead: notifier.markAsRead,
          onSpreadChanged: (index) => setState(() => _spreadIndex = index),
          onUserTurn: () => _userTurned = true,
          singleColumnWidth: _singlePageWidth,
        );
      },
    );
  }
}

/// 上下滑入的工具栏槽位。
///
/// 收起时**必须 IgnorePointer**：否则透明但仍在命中区的顶栏会吃掉书页顶部的
/// 点击（那一片正是"点空白收起工具栏"和查词要用的）。
class _ChromeSlot extends StatelessWidget {
  const _ChromeSlot({
    required this.visible,
    required this.alignment,
    required this.hiddenOffset,
    required this.child,
  });

  final bool visible;
  final Alignment alignment;
  final Offset hiddenOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : hiddenOffset,
          duration: AppMotion.base,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: AppMotion.base,
            child: child,
          ),
        ),
      ),
    );
  }
}
