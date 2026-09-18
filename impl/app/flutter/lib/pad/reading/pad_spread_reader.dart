import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/components/app_button.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../domain/model/article.dart';
import '../../domain/tts/tts_engine.dart' show kTitleParagraphIndex;
import '../../ui/reading/reading_controller.dart' show ArticleSentence;
import '../../ui/reading/reading_widgets.dart';
import '../../ui/reading/translation_visibility.dart';
import '../pad_layout.dart';
import 'article_paginator.dart';
import 'reading_block.dart';

/// 单栏模式那一列的 key（测试用来量居中与宽度——段落 widget 会收缩到
/// 文本宽度，量不出列宽）。
const Key padSingleColumnKey = ValueKey('pad-single-column');

/// 书页中缝宽（含中心 1px 竖线）。
const double kSpreadGutter = 56;

/// 页内上下留白（对照手机 ListView 的首尾）。
const double kPageTopPadding = AppSpacing.md;
const double kPageBottomPadding = AppSpacing.xs;

/// 页边点击区最小宽度：窄于此则不启用页边点击（退化为仅横滑）。
const double kEdgeTapMinWidth = 44;

/// 书页模式阅读器（**沉浸式**）：一次显示相邻两页，整屏翻页。
///
/// 与手机阅读页（单列无限滚动）是两棵独立的界面树，互不影响。
///
/// 沉浸的做法：**本组件不画任何栏**——顶栏 / 底栏 / 页码胶囊全部由外层
/// [PadReadingScreen] 以覆盖层叠在书页之上，书页本身占满整屏。竖向空间因此
/// 全部留给正文（改造前常驻的顶栏 + 底部播放条吃掉约 110dp）。
///
/// - 翻页：PageView 原生横滑；页边留白区点击（正文内的点按留给查词）
/// - 帧内不测量：分页由 [ArticlePaginator] 预先算好，本组件只负责渲染
/// - 滚动不重建书页：书页里的 `ReadingParagraph` 每次重建都会给每个单词新建
///   一个 `TapGestureRecognizer`（只在 dispose 释放），整屏重建会在一次滑动
///   里堆积成千上万个 recognizer，故重建范围必须收窄。
///
/// 「是否已读」由块列表本身表达（已读的文章不产生 [MarkAsReadBlock]），
/// 本组件不需要额外的 isReadCompleted 开关。
class PadSpreadReader extends StatefulWidget {
  const PadSpreadReader({
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
    this.singleColumnWidth,
  });

  final PaginatedArticle paginated;

  /// 非 null = **单栏模式**（整篇只占一页时的退化形态）：不再左右分屏，
  /// 只渲染这一页并把它居中到该宽度，两侧留白对称。见
  /// [PadLayout.singleColumnMaxWidth]。
  final double? singleColumnWidth;

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
  State<PadSpreadReader> createState() => _PadSpreadReaderState();
}

class _PadSpreadReaderState extends State<PadSpreadReader> {
  @override
  Widget build(BuildContext context) {
    final spreadCount = widget.paginated.spreadCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 书页内容区 = 可用宽 − 左右留白，上限 [PadLayout.spreadMaxWidth]
        // （保证单页正文不超过可读行宽）。
        final spreadWidth =
            (constraints.maxWidth - PadLayout.pagePadding * 2).clamp(
              0.0,
              PadLayout.spreadMaxWidth,
            );
        // 单栏模式：整篇一页放得下，不用左右分屏（否则右半屏是死区）。
        // 仍走 PageView（itemCount=1）——页码胶囊与 onSpreadChanged 的接线
        // 与书页模式完全一致，不必在阅读页里分叉两套。
        final columnWidth = widget.singleColumnWidth;
        if (columnWidth != null) {
          return PageView.builder(
            controller: widget.pageController,
            itemCount: 1,
            onPageChanged: widget.onSpreadChanged,
            itemBuilder: (context, _) => Center(
              child: SizedBox(
                key: padSingleColumnKey,
                width: columnWidth,
                child: _buildPage(0),
              ),
            ),
          );
        }
        return NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            // dragDetails != null → 手指拖动（animateToPage 的程序化翻页
            // dragDetails 为 null，不算用户翻页）
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
              onNext: index >= spreadCount - 1 ? null : () => _go(index + 1),
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
      children: [for (final block in page.blocks) _buildBlock(block)],
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
///
/// 箭头用最浅的 hairline 色：既是"这里可以点"的提示，又几乎不干扰阅读。
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

/// 跨页序号（可含小数，翻页动画中）→ 右页页号（左页恒为奇数页）。
///
/// **四舍五入而非向下取整**：翻页动画中小数代表"正落在哪两跨之间"，读者关心
/// 的是"松手会停在哪里"，所以过半即显示目标页——页码因此能在拖动过程中实时
/// 跟随手指，而不是等翻页落定才跳。
///
/// 提成纯函数是因为它同时被页码胶囊与其测试消费；`pageController` 在首帧
/// 尚无 client，换算必须能在"没有控制器"时也给出确定值（传 0）。
int rightPageNumberOf(double spread, int totalPages) =>
    math.min((spread.round() + 1) * 2, totalPages);
