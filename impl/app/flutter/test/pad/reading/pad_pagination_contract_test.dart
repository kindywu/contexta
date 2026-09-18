import 'package:contexta/core/theme/app_theme.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/pad/pad_layout.dart';
import 'package:contexta/pad/reading/article_paginator.dart';
import 'package:contexta/pad/reading/pad_reading_chrome.dart';
import 'package:contexta/pad/reading/pad_spread_reader.dart';
import 'package:contexta/pad/reading/pad_paginator_factory.dart';
import 'package:contexta/pad/reading/reading_block.dart';
import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真机文章在真机几何下的分页/渲染一致性回归。
///
/// 2026-09-18 平板实测发现：换成本次沉浸式的几何（书页 1180 宽 / 底部让出
/// 56dp）后，某篇文章第 2 页出现 "BOTTOM OVERFLOWED BY 3.0 PIXELS"——分页器
/// 认为放得下，渲染说放不下。本文件用**真机上那篇文章的原文**把差距钉死：
/// 分页高与渲染高必须一致，否则测试直接红。
///
/// 为什么必须用真文章：合成等宽文字的用例（`pad_spread_reader_test` 里的填充
/// 段）永远落在整行上，测不出真实换行边界处的度量差异。
const _paragraphs = [
  ArticleParagraph(id: 1, orderIndex: 0, englishText: 'Many people believe social media brings us closer together, but I disagree.', chineseTranslation: '很多人认为社交媒体拉近了我们的距离，但我不同意。'),
  ArticleParagraph(id: 2, orderIndex: 1, englishText: 'In reality, these platforms often create anxiety and loneliness instead of connection.', chineseTranslation: '事实上，这些平台常常带来焦虑和孤独，而非连接。'),
  ArticleParagraph(id: 3, orderIndex: 2, englishText: 'When we scroll through perfect photos and happy updates, we compare our real lives to unrealistic images.', chineseTranslation: '当我们刷到完美的照片和快乐的动态时，我们会拿自己的真实生活与不切实际的画面比较。'),
  ArticleParagraph(id: 4, orderIndex: 3, englishText: 'This comparison makes us feel inadequate and unhappy.', chineseTranslation: '这种比较让我们感到不足和不开心。'),
  ArticleParagraph(id: 5, orderIndex: 4, englishText: 'Furthermore, social media steals our time and attention.', chineseTranslation: '此外，社交媒体偷走了我们的时间和注意力。'),
  ArticleParagraph(id: 6, orderIndex: 5, englishText: 'People spend hours each day staring at screens, ignoring the friends and family sitting right next to them.', chineseTranslation: '人们每天花几个小时盯着屏幕，忽略了坐在身边的亲友。'),
  ArticleParagraph(id: 7, orderIndex: 6, englishText: 'True friendship requires real conversation and shared experiences, not just likes and emojis.', chineseTranslation: '真正的友谊需要真实的对话和共同的经历，而不仅仅是点赞和表情符号。'),
  ArticleParagraph(id: 8, orderIndex: 7, englishText: 'Another serious problem is the spread of misinformation.', chineseTranslation: '另一个严重的问题是错误信息的传播。'),
  ArticleParagraph(id: 9, orderIndex: 8, englishText: 'False news travels quickly on these platforms, and many people cannot tell what is true.', chineseTranslation: '假新闻在这些平台上传播得很快，很多人分不清真假。'),
  ArticleParagraph(id: 10, orderIndex: 9, englishText: 'This confusion harms our society and even endangers public health.', chineseTranslation: '这种混乱伤害我们的社会，甚至危及公共健康。'),
  ArticleParagraph(id: 11, orderIndex: 10, englishText: 'Of course, social media has some benefits.', chineseTranslation: '当然，社交媒体也有一些好处。'),
  ArticleParagraph(id: 12, orderIndex: 11, englishText: 'It helps us stay in touch with distant friends and discover new ideas.', chineseTranslation: '它帮助我们与远方的朋友保持联系，并发现新的想法。'),
  ArticleParagraph(id: 13, orderIndex: 12, englishText: 'However, these advantages do not outweigh the damage.', chineseTranslation: '然而，这些优点并不能抵消它所造成的伤害。'),
  ArticleParagraph(id: 14, orderIndex: 13, englishText: 'If we truly care about our well-being, we should limit our time on social media and focus on real-world relationships.', chineseTranslation: '如果我们真的在乎自己的幸福，就应该限制使用社交媒体的时间，专注于现实世界中的人际关系。'),
  ArticleParagraph(id: 15, orderIndex: 14, englishText: 'The benefits of genuine human connection far exceed anything a screen can offer.', chineseTranslation: '真实人际连接的好处远远超过屏幕所能提供的一切。'),
];

void main() {
  // 真机铺开尺寸：1280×800dp 横屏 @2x
  const viewport = Size(1280, 800);

  /// 与 PadReadingScreen 完全同款的口径：书页宽 / 页高都从同一批常量推导。
  ({double pageWidth, double pageHeight}) geometry() {
    final spreadWidth =
        (viewport.width - PadLayout.pagePadding * 2).clamp(
          0.0,
          PadLayout.spreadMaxWidth,
        );
    final pageWidth = (spreadWidth - kSpreadGutter) / 2;
    final pageHeight = (viewport.height - PadLayout.pagePillRowHeight) -
        kPageTopPadding -
        kPageBottomPadding;
    return (pageWidth: pageWidth, pageHeight: pageHeight);
  }

  testWidgets('真文章：每页渲染高不超过分页高（无 RenderFlex 溢出）', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final g = geometry();
    // 用与生产同一个工厂：测量样式必须按渲染路径（Text vs RichText）对齐，
    // 否则又回到"测量 1 行 / 渲染 2 行"的老 bug 上。
    late final ArticlePaginator paginator;
    // 注意：必须在 Scaffold 内部读 DefaultTextStyle —— Scaffold 的 body 外面
    // 包着一层 Material，它才把 theme.textTheme.bodyMedium 设为 ambient；
    // 在 MaterialApp.home 那一层读到的是 WidgetsApp 的错误样式，不是渲染现场。
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              paginator = buildPadPaginator(
                DefaultTextStyle.of(context).style,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final controller = PageController();
    addTearDown(controller.dispose);

    final keys = <int, GlobalObjectKey>{};
    GlobalObjectKey pKey(int i) =>
        keys.putIfAbsent(i, () => GlobalObjectKey('p-$i'));
    final textKeys = <int, GlobalObjectKey>{};
    GlobalObjectKey tKey(int i) =>
        textKeys.putIfAbsent(i, () => GlobalObjectKey('t-$i'));

    final paginated = paginator.paginate(
      blocks: [
        const TitleBlock('Social Media Does More Harm Than Good'),
        for (final p in _paragraphs.indexed)
          ParagraphBlock(
            index: p.$1,
            englishText: p.$2.englishText,
            chineseTranslation: p.$2.chineseTranslation,
          ),
      ],
      pageWidth: g.pageWidth,
      pageHeight: g.pageHeight,
      bodyTextScaler: TextScaler.noScaling,
      labelTextScaler: TextScaler.noScaling,
      translationMode: TranslationMode.full,
    );

    for (var spread = 0; spread < paginated.spreadCount; spread++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: Column(
                children: [
                  Expanded(
                    child: PadSpreadReader(
                      paginated: paginated,
                      pageController: controller,
                      title: 'Social Media Does More Harm Than Good',
                      paragraphs: _paragraphs,
                      sentencesByParagraph: const [],
                      translationMode: TranslationMode.full,
                      revealedParagraphs: const {},
                      vocabularyWords: const {},
                      speakingParagraphIndex: null,
                      speakingSentenceIndex: null,
                      paragraphKey: pKey,
                      paragraphTextKey: tKey,
                      onWordClick: (_) {},
                      onTranslationClick: (_) {},
                      onPlayParagraph: (_) {},
                      onMarkAsRead: () {},
                      onSpreadChanged: (_) {},
                      onUserTurn: () {},
                    ),
                  ),
                  SizedBox(
                    height: PadLayout.pagePillRowHeight,
                    child: Center(
                      child: PadPagePill(
                        pageController: controller,
                        totalPages: paginated.pages.length,
                        isSpeaking: false,
                        onToggleChrome: () {},
                        onTogglePlayback: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (spread > 0) {
        controller.jumpToPage(spread);
      }
      await tester.pumpAndSettle();

      final overflow = tester.takeException();
      expect(
        overflow,
        isNull,
        reason: '第 ${spread + 1} 跨页渲染溢出（分页高 ${g.pageHeight}）',
      );

      // 双向校验：本跨页每个块的分页高度 == 渲染高度（差 1px 内）。
      // 只能在当前跨页上量——PageView 只挂载当前跨页的页。
      for (final pageIndex in [spread * 2, spread * 2 + 1]) {
        if (pageIndex >= paginated.pages.length) continue;
        for (final block in paginated.pages[pageIndex].blocks) {
          if (block is! ParagraphBlock) continue;
          final rendered = tester
              .getRect(find.byKey(pKey(block.index)))
              .height;
          final measured = paginator.heightOf(
            block,
            pageWidth: g.pageWidth,
            bodyTextScaler: TextScaler.noScaling,
            labelTextScaler: TextScaler.noScaling,
            translationMode: TranslationMode.full,
          );
          expect(
            rendered,
            closeTo(measured, 1),
            reason:
                '第 ${block.index} 段：渲染 $rendered vs 测量 $measured'
                '（不一致 = 换行位置对不上，页尾会溢出）',
          );
        }
      }
    }
  });
}
