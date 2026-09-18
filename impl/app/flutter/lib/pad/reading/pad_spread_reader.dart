import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/components/app_button.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/theme/app_type.dart';
import '../../../domain/model/article.dart';
import '../../../domain/tts/tts_engine.dart' show kTitleParagraphIndex;
import '../reading_controller.dart' show ArticleSentence;
import '../reading_widgets.dart';
import '../translation_visibility.dart';
import 'article_paginator.dart';
import 'reading_block.dart';

/// 中缝宽（含中心 1px 竖线）。
const double kSpreadGutter = 40;

/// 书页内容区最大宽（超宽屏居中留白，保证单页正文约 530dp ≈ 59 字符/行）。
const double kSpreadMaxWidth = 1100;

/// 页内上下留白（对照手机 ListView 的首尾 SizedBox）。
const double kPageTopPadding = AppSpacing.sm;
const double kPageBottomPadding = AppSpacing.xs;

/// 底部页码行的高度（定值，见 [_PageIndicator]）。
///
/// 页码行在 PageView **下方**，页内容盒高度 = 可用高 − 本值 − 页内上下留白；
/// 分页器必须按同一个式子算页高，否则会往页里塞过多内容（溢出页底）。
const double kPageIndicatorHeight = 28;

/// 页边点击区最小宽度：窄于此则不启用页边点击（退化为仅横滑）。
const double kEdgeTapMinWidth = 24;

/// 书页模式阅读器：一次显示相邻两页，整屏翻页。
///
/// - 翻页：PageView 原生横滑；页边空白区点击（正文内的点按留给查词）
/// - 帧内不测量：分页由 [ArticlePaginator] 预先算好，本组件只负责渲染
/// - 滚动不重建本组件：页码由 [_PageIndicator] 自己监听 [pageController]。
///   书页里的 `ReadingParagraph` 每次重建都会给每个单词新建一个
///   `TapGestureRecognizer`（只在 dispose 释放），整屏重建会在一次滑动里
///   堆积成千上万个 recognizer，故重建范围必须收窄到那一行 Text。
///
/// 「是否已读」由块列表本身表达（已读的文章不产生 [MarkAsReadBlock]），
/// 本组件不需要额外的 isReadCompleted 开关。
class SpreadReader extends StatefulWidget {
  const SpreadReader({
    super.key,
    required this.paginated,
    required this.pageController,
    required this.title,
    required this.paragraphs,
    required this.sentencesByParagraph,
    required this.translationMode,
    required this.revealedParagraphs,
    required this.vocabularyWords,
    required this.speakingParagraphIndex,
    required this.speakingSentenceIndex,
    required this.paragraphKey,
    required this.paragraphTextKey,
    required this.onWordClick,
    required this.onTranslationClick,
    required this.onPlayParagraph,
    required this.onMarkAsRead,
    required this.onSpreadChanged,
    required this.onUserTurn,
  });

  final PaginatedArticle paginated;

  /// 跨页控制器由外部持有（朗读自动翻页要按段落 → 页查表跳页）。
  final PageController pageController;
  final String title;
  final List<ArticleParagraph> paragraphs;
  final List<List<ArticleSentence>> sentencesByParagraph;
  final TranslationMode translationMode;
  final Set<int> revealedParagraphs;
  final Set<String> vocabularyWords;
  final int? speakingParagraphIndex;
  final int? speakingSentenceIndex;
  final GlobalObjectKey Function(int index) paragraphKey;
  final GlobalObjectKey Function(int index) paragraphTextKey;
  final ValueChanged<String> onWordClick;
  final ValueChanged<int> onTranslationClick;
  final ValueChanged<int> onPlayParagraph;
  final VoidCallback onMarkAsRead;
  final ValueChanged<int> onSpreadChanged;

  /// 用户手动翻页（拖拽或页边点击）时回调（供 TTS 自动翻页「跳过一次」用）。
  final VoidCallback onUserTurn;

  @override
  State<SpreadReader> createState() => _SpreadReaderState();
}

class _SpreadReaderState extends State<SpreadReader> {
  @override
  Widget build(BuildContext context) {
    final pageCount = widget.paginated.pages.length;
    final spreadCount = widget.paginated.spreadCount;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spreadWidth =
                  (constraints.maxWidth - AppPage.horizontalPadding * 2).clamp(
                    0.0,
                    kSpreadMaxWidth,
                  );
              return NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  // dragDetails != null → 手指拖动（animateToPage 的
                  // 程序化翻页 dragDetails 为 null，不算用户翻页）
                  if (notification.dragDetails != null) widget.onUserTurn();
                  return false;
                },
                child: PageView.builder(
                  controller: widget.pageController,
                  itemCount: spreadCount,
                  onPageChanged: widget.onSpreadChanged,
                  itemBuilder: (context, index) => _EdgeTapRow(
                    availableWidth: constraints.maxWidth,
                    spreadWidth: spreadWidth,
                    onPrevious: index == 0 ? null : () => _go(index - 1),
                    onNext: index >= spreadCount - 1
                        ? null
                        : () => _go(index + 1),
                    child: SizedBox(
                      width: spreadWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildPage(index * 2)),
                          const SizedBox(width: kSpreadGutter),
                          Expanded(child: _buildPage(index * 2 + 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _PageIndicator(
          pageController: widget.pageController,
          totalPages: pageCount,
        ),
      ],
    );
  }

  /// 页边点击翻页（唯一调用方是 [_EdgeTapRow] 左右两个点击区）。先登记
  /// 「用户手动翻页」再动画——与拖拽同义，TTS 自动翻页据此跳过一次。
  /// TTS 自动翻页走阅读页自己的 `pageController.animateToPage`，不经此处，
  /// 故不会自我抑制。
  void _go(int spreadIndex) {
    widget.onUserTurn();
    widget.pageController.animateToPage(
      spreadIndex,
      duration: AppMotion.slow,
      curve: Curves.easeInOut,
    );
  }

  Widget _buildPage(int pageIndex) {
    if (pageIndex >= widget.paginated.pages.length) {
      return const SizedBox.expand(); // 空白页：保持书页观感
    }
    final page = widget.paginated.pages[pageIndex];
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in page.blocks) _buildBlock(block),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(
        top: kPageTopPadding,
        bottom: kPageBottomPadding,
      ),
      // 兜底：单块超过整页高时该页可竖向滚动（正常文章不会触发）
      child: page.overflows ? SingleChildScrollView(child: column) : column,
    );
  }

  Widget _buildBlock(ReadingBlock block) {
    switch (block) {
      case TitleBlock():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ReadingTitle(
              text: widget.title,
              isSpeaking:
                  widget.speakingParagraphIndex == kTitleParagraphIndex,
              vocabularyWords: widget.vocabularyWords,
              onWordClick: widget.onWordClick,
            ),
            const SizedBox(height: kTitleGapBelow),
            Container(height: kTitleDividerHeight, color: AppColors.hairline),
            const SizedBox(height: kTitleGapAfterDivider),
          ],
        );

      case ParagraphBlock(:final index):
        final paragraph = widget.paragraphs[index];
        // 块间无额外间距：段落块的渲染高必须正好等于 ReadingParagraph 的高
        // （段内间距已由 ReadingParagraph 自己带，见 ArticlePaginator.heightOf），
        // 外面再包一层 Padding 会让每段多出 4dp、整页比测量值高——溢出页底。
        return ReadingParagraph(
          key: widget.paragraphKey(index),
          textKey: widget.paragraphTextKey(index),
          englishText: paragraph.englishText,
          chineseTranslation: paragraph.chineseTranslation,
          sentences: index < widget.sentencesByParagraph.length
              ? widget.sentencesByParagraph[index]
              : const [],
          speakingSentenceIndex: widget.speakingParagraphIndex == index
              ? widget.speakingSentenceIndex
              : null,
          translationMode: widget.translationMode,
          isRevealed: widget.revealedParagraphs.contains(index),
          vocabularyWords: widget.vocabularyWords,
          isSpeaking: widget.speakingParagraphIndex == index,
          onWordClick: widget.onWordClick,
          onTranslationClick: () => widget.onTranslationClick(index),
          onPlay: () => widget.onPlayParagraph(index),
        );

      case MarkAsReadBlock():
        return Padding(
          padding: const EdgeInsets.only(top: kMarkAsReadTopGap),
          child: AppButton(
            text: kMarkAsReadLabel,
            onClick: widget.onMarkAsRead,
            variant: AppButtonVariant.secondary,
          ),
        );
    }
  }
}

/// 书页左右两侧的空白点击区（正文列之外）。空白宽度不足 [kEdgeTapMinWidth]
/// 时不启用——退化为仅横滑翻页，避免误触。
///
/// 点击区是正文列的**兄弟**（不是覆盖层）：既不会挡住正文里的查词点按，
/// 只挂 onTap 也不会吞掉横滑——横拖在手势竞技场里由 PageView 的拖动胜出。
class _EdgeTapRow extends StatelessWidget {
  const _EdgeTapRow({
    required this.availableWidth,
    required this.spreadWidth,
    required this.child,
    this.onPrevious,
    this.onNext,
  });

  final double availableWidth;
  final double spreadWidth;
  final Widget child;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final edge = (availableWidth - spreadWidth) / 2;
    final enabled = edge >= kEdgeTapMinWidth;
    return Row(
      // stretch：点击区撑满整页高（否则只剩图标那一小块可点）
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: enabled && onPrevious != null
              ? _EdgeTapZone(icon: Icons.chevron_left, onTap: onPrevious!)
              : const SizedBox.shrink(),
        ),
        child,
        Expanded(
          child: enabled && onNext != null
              ? _EdgeTapZone(icon: Icons.chevron_right, onTap: onNext!)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _EdgeTapZone extends StatelessWidget {
  const _EdgeTapZone({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque：空白处也要可点（Center 之外的区域本不参与命中测试）
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Icon(icon, size: 24, color: AppColors.hairline),
      ),
    );
  }
}

/// 底部页码：右页页号 / 总页数（左页为奇数页）。
///
/// 自己监听 [pageController]（横滑中每帧、jumpToPage 都通知）：重建范围只有
/// 这一行 Text，书页内容不受影响（见 [SpreadReader] 的说明）。
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.pageController, required this.totalPages});

  final PageController pageController;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      // 定高：分页按 kPageIndicatorHeight 扣页高，行高不随字体缩放漂移
      builder: (context, _) => SizedBox(
        height: kPageIndicatorHeight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text(
            '${_rightPageNumber()} / $totalPages',
            style: AppType.textTheme.labelMedium?.copyWith(
              color: AppColors.mutedSoft,
            ),
          ),
        ),
      ),
    );
  }

  /// 右页页号（左页为奇数页）。首帧控制器尚无 client，回落到首页。
  int _rightPageNumber() {
    final spread = pageController.hasClients
        ? (pageController.page?.round() ?? 0)
        : 0;
    return math.min((spread + 1) * 2, totalPages);
  }
}
