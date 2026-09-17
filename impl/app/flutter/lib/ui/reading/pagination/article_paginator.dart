// TextPainter / TextSpan / TextScaler 由 widgets 转发（widgets 层 re-export
// painting）；WidgetSpan 与 SizedBox 本身就在 widgets 层（Flutter 3.47 起
// WidgetSpan 已从 painting 迁到 widgets，故不再 import painting）。
import 'package:flutter/widgets.dart';

import '../translation_visibility.dart';
import '../word_spans.dart';
import 'reading_block.dart';

/// 段落与译文之间的固定间距（对照 _ReadingParagraph 的 SizedBox(height: 4)）。
const double kParagraphGap = 4;

/// 标题块内的固定间距（对照手机路径：标题 → 16 → 1px 分隔线 → 24）。
const double kTitleGapBelow = 16;
const double kTitleDividerHeight = 1;
const double kTitleGapAfterDivider = 24;

/// 段尾内联播放钮的占位尺寸（对照 _InlinePlayButton：Icon(size: 18)
/// 前置 4dp 空隙）。测量必须给出同样的占位尺寸，否则页高会少算一个图标。
const double kInlinePlayGap = 4;
const Size kInlinePlayIconSize = Size(18, 18);

/// 「标记已读」块：24dp 上间距 + AppButton（文字 + 上下各 12dp padding）。
const double kMarkAsReadTopGap = 24;
const double kButtonVerticalPadding = 12;
const String kMarkAsReadLabel = '标记已读';

/// 一页：装下的块 + 已用高度 + 是否有单块超过整页高。
class ReadingPage {
  const ReadingPage({
    required this.blocks,
    required this.usedHeight,
    required this.overflows,
  });
  final List<ReadingBlock> blocks;
  final double usedHeight;
  final bool overflows;
}

/// 分页结果。
class PaginatedArticle {
  const PaginatedArticle({required this.pages, required this.pageOfParagraph});

  final List<ReadingPage> pages;

  /// 段落序号 → 页序号（书页模式做句子高亮自动翻页时纯查表，不二次测量）。
  final Map<int, int> pageOfParagraph;

  /// 跨页数（每跨页显示相邻两页）。
  int get spreadCount => (pages.length + 1) ~/ 2;

  int? pageOf(int paragraphIndex) => pageOfParagraph[paragraphIndex];
}

/// 分页引擎：把块序列按页高打包成页。
///
/// 测高用 [TextPainter]（纯 Dart，可离线单测），样式与 span 构建必须与真实
/// 渲染同源——见 AppType.readingBody / buildWordSpans。
class ArticlePaginator {
  const ArticlePaginator({
    required this.bodyStyle,
    required this.translationStyle,
    required this.titleStyle,
    required this.buttonLabelStyle,
  });

  final TextStyle bodyStyle;
  final TextStyle translationStyle;
  final TextStyle titleStyle;
  final TextStyle buttonLabelStyle;

  PaginatedArticle paginate({
    required List<ReadingBlock> blocks,
    required double pageWidth,
    required double pageHeight,
    required TextScaler textScaler,
    required TranslationMode translationMode,
  }) {
    final pages = <ReadingPage>[];
    var current = <ReadingBlock>[];
    var used = 0.0;
    var overflows = false;

    void flush() {
      pages.add(
        ReadingPage(
          blocks: List.unmodifiable(current),
          usedHeight: used,
          overflows: overflows,
        ),
      );
      current = <ReadingBlock>[];
      used = 0;
      overflows = false;
    }

    for (final block in blocks) {
      final height = heightOf(
        block,
        pageWidth: pageWidth,
        textScaler: textScaler,
        translationMode: translationMode,
      );
      if (current.isNotEmpty && used + height > pageHeight) flush();
      current.add(block);
      used += height;
      // 单块自身超过整页高：独占一页（该页渲染时允许竖向滚动兜底）
      if (used > pageHeight) {
        overflows = true;
        flush();
      }
    }
    if (current.isNotEmpty) flush();
    if (pages.isEmpty) {
      pages.add(const ReadingPage(blocks: [], usedHeight: 0, overflows: false));
    }

    final pageOfParagraph = <int, int>{};
    for (var p = 0; p < pages.length; p++) {
      for (final block in pages[p].blocks) {
        if (block is ParagraphBlock) pageOfParagraph[block.index] = p;
      }
    }
    return PaginatedArticle(pages: pages, pageOfParagraph: pageOfParagraph);
  }

  /// 单块高度（块内间距已含；块间无额外间距——与手机路径的 Column 一致）。
  double heightOf(
    ReadingBlock block, {
    required double pageWidth,
    required TextScaler textScaler,
    required TranslationMode translationMode,
  }) {
    switch (block) {
      case TitleBlock(:final text):
        final titleHeight = _paintHeight(
          TextSpan(
            style: titleStyle,
            children: buildWordSpans(
              text: text,
              style: null,
              vocabularyWords: const {},
              recognizerFor: null,
            ),
          ),
          pageWidth,
          textScaler,
        );
        return titleHeight +
            kTitleGapBelow +
            kTitleDividerHeight +
            kTitleGapAfterDivider;

      case ParagraphBlock():
        return _paragraphHeight(
          block,
          pageWidth: pageWidth,
          textScaler: textScaler,
          translationMode: translationMode,
        );

      case MarkAsReadBlock():
        final labelHeight = _paintHeight(
          TextSpan(text: kMarkAsReadLabel, style: buttonLabelStyle),
          pageWidth,
          textScaler,
        );
        return kMarkAsReadTopGap +
            labelHeight +
            kButtonVerticalPadding * 2;
    }
  }

  double _paragraphHeight(
    ParagraphBlock block, {
    required double pageWidth,
    required TextScaler textScaler,
    required TranslationMode translationMode,
  }) {
    // 英文正文：与 ReadingParagraph 渲染的 span 树同构（含段尾内联播放钮的
    // 两个 WidgetSpan），颜色/底色不影响度量，故测量用中性样式。
    final span = TextSpan(
      style: bodyStyle,
      children: [
        ...buildWordSpans(
          text: block.englishText,
          style: null,
          vocabularyWords: const {},
          recognizerFor: null,
        ),
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(width: kInlinePlayGap),
        ),
        // 非 const：Size.width / Size.height 是 getter，不能出现在常量表达式里
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(
            width: kInlinePlayIconSize.width,
            height: kInlinePlayIconSize.height,
          ),
        ),
      ],
    );

    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: null,
    )..setPlaceholderDimensions(
        const [
          PlaceholderDimensions(
            size: Size(kInlinePlayGap, 0),
            alignment: PlaceholderAlignment.middle,
          ),
          PlaceholderDimensions(
            size: kInlinePlayIconSize,
            alignment: PlaceholderAlignment.middle,
          ),
        ],
      );
    painter.layout(maxWidth: pageWidth);
    var height = painter.height;
    painter.dispose();

    // 段内固定间距（SizedBox(height: 4)）在手机路径无条件存在
    height += kParagraphGap;

    if (translationMode == TranslationMode.hidden) return height;

    final translation = TextPainter(
      text: TextSpan(text: block.chineseTranslation, style: translationStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: null,
    )..layout(maxWidth: pageWidth);
    height += translation.height + kParagraphGap;
    translation.dispose();
    return height;
  }

  double _paintHeight(InlineSpan span, double maxWidth, TextScaler textScaler) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
