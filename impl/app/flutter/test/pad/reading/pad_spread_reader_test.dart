import 'dart:async';

import 'package:contexta/core/theme/app_type.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/pad/reading/article_paginator.dart';
import 'package:contexta/pad/reading/reading_block.dart';
import 'package:contexta/pad/pad_layout.dart';
import 'package:contexta/pad/reading/pad_reading_chrome.dart';
import 'package:contexta/pad/reading/pad_spread_reader.dart';
import 'package:contexta/ui/reading/reading_widgets.dart';
import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _paragraphs = [
  ArticleParagraph(id: 1, orderIndex: 0, englishText: 'First paragraph.', chineseTranslation: '第一段。'),
  ArticleParagraph(id: 2, orderIndex: 1, englishText: 'Second paragraph.', chineseTranslation: '第二段。'),
  ArticleParagraph(id: 3, orderIndex: 2, englishText: 'Third paragraph.', chineseTranslation: '第三段。'),
  ArticleParagraph(id: 4, orderIndex: 3, englishText: 'Fourth paragraph.', chineseTranslation: '第四段。'),
];

/// 每段独占一页 → 4 页 / 2 跨页，便于断言左右页与翻页。
PaginatedArticle fourPages() => PaginatedArticle(
  pages: const [
    ReadingPage(blocks: [ParagraphBlock(index: 0, englishText: 'First paragraph.', chineseTranslation: '第一段。')], usedHeight: 10, overflows: false),
    ReadingPage(blocks: [ParagraphBlock(index: 1, englishText: 'Second paragraph.', chineseTranslation: '第二段。')], usedHeight: 10, overflows: false),
    ReadingPage(blocks: [ParagraphBlock(index: 2, englishText: 'Third paragraph.', chineseTranslation: '第三段。')], usedHeight: 10, overflows: false),
    ReadingPage(blocks: [ParagraphBlock(index: 3, englishText: 'Fourth paragraph.', chineseTranslation: '第四段。')], usedHeight: 10, overflows: false),
  ],
  pageOfParagraph: const {0: 0, 1: 1, 2: 2, 3: 3},
);

ArticlePaginator buildPaginator() => ArticlePaginator(
  bodyStyle: AppType.readingBody,
  translationStyle: AppType.readingTranslation,
  titleStyle: AppType.readingTitle,
  buttonLabelStyle: AppType.textTheme.titleSmall!,
);

void main() {
  final keys = <int, GlobalObjectKey>{};
  GlobalObjectKey paragraphKey(int i) =>
      keys.putIfAbsent(i, () => GlobalObjectKey('reading-para-$i'));
  final textKeys = <int, GlobalObjectKey>{};
  GlobalObjectKey paragraphTextKey(int i) =>
      textKeys.putIfAbsent(i, () => GlobalObjectKey('reading-para-text-$i'));

  late PageController controller;
  var spreadIndex = 0;
  var userTurns = 0;
  var tappedWords = <String>[];
  var chromeToggles = 0;

  setUp(() {
    controller = PageController();
    spreadIndex = 0;
    userTurns = 0;
    tappedWords = [];
    chromeToggles = 0;
    keys.clear();
    textKeys.clear();
  });

  tearDown(() => controller.dispose());

  Future<void> pumpReaderWith(
    WidgetTester tester,
    PaginatedArticle paginated,
    List<ArticleParagraph> paragraphs, {
    TranslationMode mode = TranslationMode.full,
  }) async {
    // 与 PadReadingScreen 同款组合：书页占满上方，底部让出一条页码胶囊带。
    // 页码不在 PadSpreadReader 里（沉浸式重设计把它提到了外层覆盖层），
    // 所以测试也要按生产组合来搭，否则量到的几何与真机不一致。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: PadSpreadReader(
                  paginated: paginated,
                  pageController: controller,
                  title: 'A Title',
                  paragraphs: paragraphs,
                  sentencesByParagraph: const [[], [], [], []],
                  translationMode: mode,
                  revealedParagraphs: const {},
                  vocabularyWords: const {},
                  speakingParagraphIndex: null,
                  speakingSentenceIndex: null,
                  paragraphKey: paragraphKey,
                  paragraphTextKey: paragraphTextKey,
                  onWordClick: tappedWords.add,
                  onTranslationClick: (_) {},
                  onPlayParagraph: (_) {},
                  onMarkAsRead: () {},
                  onSpreadChanged: (i) => spreadIndex = i,
                  onUserTurn: () => userTurns++,
                ),
              ),
              SizedBox(
                height: PadLayout.pagePillRowHeight,
                child: Center(
                  child: PadPagePill(
                    pageController: controller,
                    totalPages: paginated.pages.length,
                    isSpeaking: false,
                    onToggleChrome: () => chromeToggles++,
                    onTogglePlayback: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpReader(WidgetTester tester, PaginatedArticle paginated) =>
      pumpReaderWith(tester, paginated, _paragraphs);

  testWidgets('第一跨页显示第 1、2 页内容，第 3 页不构建', (tester) async {
    await pumpReader(tester, fourPages());
    // 正文是 ReadingParagraph 里的独立 RichText（非 Text），查找须开 findRichText
    expect(find.textContaining('First paragraph.', findRichText: true), findsOneWidget);
    expect(find.textContaining('Second paragraph.', findRichText: true), findsOneWidget);
    expect(find.textContaining('Third paragraph.', findRichText: true), findsNothing);
  });

  testWidgets('页码指示显示右页页号 / 总页数', (tester) async {
    await pumpReader(tester, fourPages());
    expect(find.text('2 / 4'), findsOneWidget);
  });

  testWidgets('点击右侧页边空白翻到下一跨页（且登记为用户手动翻页）', (tester) async {
    // 视口 1600×813 逻辑像素（DPR=1）：跨页内容 1100 居中 → 左右页边各
    // (1600 − 1100) / 2 = 250，远大于 kEdgeTapMinWidth(24)，页边点击才启用。
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpReader(tester, fourPages());
    expect(
      tester.getSize(find.byType(PadSpreadReader)),
      const Size(1600, 813 - PadLayout.pagePillRowHeight),
      reason: '底部让出的胶囊带不计入书页',
    );

    await tester.tapAt(const Offset(1550, 400)); // 右侧页边（x ∈ [1350, 1600)）
    await tester.pumpAndSettle();

    expect(spreadIndex, 1);
    // 页边点击是点按不是拖动，但对读者而言同样是手动翻页——必须登记，
    // 否则下一次 TTS 切句会立刻把人拽回朗读位置
    expect(userTurns, 1, reason: '页边点击须登记为用户手动翻页');
  });

  testWidgets('页边点击区不吞横滑：从页边起手的拖动仍翻页', (tester) async {
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpReader(tester, fourPages());

    // 从右页边（点击区）起手横拖超过半屏宽 → PageView 吸附到下一跨页
    await tester.dragFrom(const Offset(1550, 400), const Offset(-900, 0));
    await tester.pumpAndSettle();

    expect(spreadIndex, 1);
    expect(userTurns, greaterThan(0)); // 手指拖动（程序化翻页不计）
  });

  testWidgets('拖动中页码实时更新，且不重建书页（重建范围只有页码行）', (tester) async {
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpReader(tester, fourPages());
    expect(find.text('2 / 4'), findsOneWidget);

    // 书页里的段落 widget 实例：整屏重建会换新实例（进而给每个单词重建
    // TapGestureRecognizer，一次滑动堆积成千上万个）
    final paragraphBefore = tester.widget<ReadingParagraph>(
      find.byType(ReadingParagraph).first,
    );

    final gesture = await tester.startGesture(const Offset(800, 400));
    await gesture.moveBy(const Offset(-900, 0)); // 拖过半屏宽
    await tester.pump(); // 不松手、不 settle：此刻仍是拖动中

    expect(
      find.text('4 / 4'),
      findsOneWidget,
      reason: '页码须在拖动中实时跟随，不能等翻页落定',
    );
    expect(
      identical(
        tester.widget<ReadingParagraph>(find.byType(ReadingParagraph).first),
        paragraphBefore,
      ),
      isTrue,
      reason: '拖动中不得重建书页——ReadingParagraph 实例须保持不变',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(spreadIndex, 1);
  });

  testWidgets('正文内点按单词仍走查词（页边点击区不覆盖正文列）', (tester) async {
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpReader(tester, fourPages());
    // 页边点击区启用时（左右各 250）正文仍可点词
    final textBox = tester.getRect(find.byKey(paragraphTextKey(0)));
    await tester.tapAt(Offset(textBox.left + 8, textBox.center.dy)); // 首个单词
    await tester.pumpAndSettle();

    expect(tappedWords, ['first']); // 点按回调收到归一化后的单词
  });

  testWidgets('奇数次总页数时右页为空（左页仍渲染）', (tester) async {
    final three = PaginatedArticle(
      pages: fourPages().pages.sublist(0, 3),
      pageOfParagraph: const {0: 0, 1: 1, 2: 2},
    );
    await pumpReader(tester, three);
    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.textContaining('Third paragraph.', findRichText: true), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    // 程序化翻页（TTS 自动翻页同路径）不得登记为用户翻页——否则朗读自己
    // 翻的页会把下一次自动翻页也吃掉。TTS 走的就是 animateToPage。
    expect(userTurns, 0, reason: '程序化跳页不算用户手动翻页');
    // 不 await：动画要靠 pump 推进，直接 await 会死等到测试超时
    unawaited(
      controller.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      ),
    );
    await tester.pumpAndSettle();
    expect(userTurns, 0, reason: '程序化动画翻页同样不算用户手动翻页');
  });

  group('单栏模式（整篇一页放得下时的退化形态）', () {
    testWidgets('不给 singleColumnWidth → 走书页两栏（左页 + 右页）', (tester) async {
      await pumpReader(tester, fourPages());

      // 第一跨页同时渲染第 1、2 页
      expect(
        find.textContaining('First paragraph.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Second paragraph.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('给 singleColumnWidth → 只渲染一栏，且**居中**（两侧留白对称）', (tester) async {
      tester.view.physicalSize = const Size(1600, 813);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const columnWidth = 760.0;
      final single = PaginatedArticle(
        pages: [
          ReadingPage(
            blocks: const [
              ParagraphBlock(
                index: 0,
                englishText: 'First paragraph.',
                chineseTranslation: '第一段。',
              ),
            ],
            usedHeight: 10,
            overflows: false,
          ),
        ],
        pageOfParagraph: const {0: 0},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1600,
              height: 813,
              child: PadSpreadReader(
                paginated: single,
                pageController: controller,
                title: 'A Title',
                paragraphs: _paragraphs,
                sentencesByParagraph: const [[]],
                translationMode: TranslationMode.full,
                revealedParagraphs: const {},
                vocabularyWords: const {},
                speakingParagraphIndex: null,
                speakingSentenceIndex: null,
                paragraphKey: paragraphKey,
                paragraphTextKey: paragraphTextKey,
                onWordClick: tappedWords.add,
                onTranslationClick: (_) {},
                onPlayParagraph: (_) {},
                onMarkAsRead: () {},
                onSpreadChanged: (i) => spreadIndex = i,
                onUserTurn: () {},
                singleColumnWidth: columnWidth,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 只渲染第一页；第 2 页不存在于树里
      expect(
        find.textContaining('First paragraph.', findRichText: true),
        findsOneWidget,
      );

      // 居中：内容列左右留白相等（这是"单栏"与"书页左页"的唯一可见差别）。
      // 量的是列本身——ReadingParagraph 是 Column(crossAxisAlignment: start)，
      // 会横向收缩到文本宽度，量段落 rect 得不到列宽。
      final rect = tester.getRect(find.byKey(padSingleColumnKey));
      expect(rect.width, moreOrLessEquals(columnWidth, epsilon: 1));
      final leftGap = rect.left;
      final rightGap = 1600 - rect.right;
      expect(
        (leftGap - rightGap).abs(),
        lessThan(2),
        reason: '两侧留白须对称（左 $leftGap / 右 $rightGap）——否则看起来像书页模式坏了',
      );
    });
  });

  testWidgets('真实分页结果渲染在页内不溢出：页被填满时末块底边不越页底', (tester) async {
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 分页器与渲染唯一共享的几何量是"页码胶囊带高度"——它是显式布局常量
    // （PadLayout.pagePillRowHeight），书页高度 = 视口 − 它。这里直接引用该
    // 常量；若哪天书页改成覆盖在胶囊带上，这个等式就会失效，测试会先红。
    const indicatorHeight = PadLayout.pagePillRowHeight;
    expect(
      kPageTopPadding + kPageBottomPadding + indicatorHeight,
      lessThan(813),
      reason: '胶囊带加页内留白不能吃掉整屏',
    );

    // 视口 1600 → 跨页 1100 → 单页 (1100 − kSpreadGutter) / 2 = 530
    const pageWidth = 530.0;
    const fillerText = 'Pack the page tightly with words.';
    const fillerTranslation = '把页面填满。';
    const targetContentHeight = 420.0;

    final paginator = buildPaginator();

    // 译文显示/隐藏是两条测量分支（段尾间距不同），两条都得与渲染同源
    for (final mode in const [TranslationMode.full, TranslationMode.hidden]) {
      final reason = '（模式 $mode）';
      double heightOf(ReadingBlock block) => paginator.heightOf(
        block,
        pageWidth: pageWidth,
        bodyTextScaler: TextScaler.noScaling,
        labelTextScaler: TextScaler.noScaling,
        translationMode: mode,
      );

      final titleHeight = heightOf(const TitleBlock('A Title'));
      final fillerHeight = heightOf(
        const ParagraphBlock(
          index: 0,
          englishText: fillerText,
          chineseTranslation: fillerTranslation,
        ),
      );

      // 页内容盒高度取「标题 + N 段」的整数倍：页被填到一丝不剩——任何测量/
      // 渲染漂移都会立刻变成 RenderFlex 溢出，这正是本测试要抓的失败模式。
      final fillerCount =
          ((targetContentHeight - titleHeight) / fillerHeight).ceil();
      final contentHeight = titleHeight + fillerCount * fillerHeight;
      expect(fillerCount, greaterThan(1), reason: reason);

      final paragraphs = [
        for (var i = 0; i < fillerCount; i++)
          ArticleParagraph(
            id: i + 1,
            orderIndex: i,
            englishText: fillerText,
            chineseTranslation: fillerTranslation,
          ),
      ];
      final paginated = paginator.paginate(
        blocks: [
          const TitleBlock('A Title'),
          for (var i = 0; i < fillerCount; i++)
            ParagraphBlock(
              index: i,
              englishText: fillerText,
              chineseTranslation: fillerTranslation,
            ),
        ],
        pageWidth: pageWidth,
        pageHeight: contentHeight,
        bodyTextScaler: TextScaler.noScaling,
        labelTextScaler: TextScaler.noScaling,
        translationMode: mode,
      );

      // 渲染高度 = 分页高度：页内容盒正好等于 contentHeight
      tester.view.physicalSize = Size(
        1600,
        contentHeight + indicatorHeight + kPageTopPadding + kPageBottomPadding,
      );
      await pumpReaderWith(tester, paginated, paragraphs, mode: mode);

      // 分页器把整篇装进了一页且填满（本测试的前提）
      expect(paginated.pages.length, 1, reason: reason);
      expect(paginated.pages.single.overflows, isFalse, reason: reason);
      expect(
        paginated.pages.single.usedHeight,
        greaterThan(contentHeight - 1),
        reason: '页须被填满——空页测不出测量/渲染漂移$reason',
      );

      // 无 RenderFlex 溢出（页已填满，多布局一个像素就会在这里报错）
      expect(tester.takeException(), isNull, reason: reason);

      // 每个块的渲染高 == 分页器算出的块高（测量/渲染同源）
      for (var i = 0; i < fillerCount; i++) {
        expect(
          tester.getRect(find.byKey(paragraphKey(i))).height,
          closeTo(fillerHeight, 1),
          reason: '第 $i 段渲染高与分页器测量高不一致$reason',
        );
      }

      // 左页最后一个块的底边落在页内容盒底边之内（容 1px 舍入）
      final lastBlock = paginated.pages.single.blocks.last as ParagraphBlock;
      final lastBlockBottom = tester
          .getRect(find.byKey(paragraphKey(lastBlock.index)))
          .bottom;
      final pageContentBottom =
          tester.getTopLeft(find.text('1 / 1')).dy - kPageBottomPadding;
      expect(
        lastBlockBottom,
        lessThanOrEqualTo(pageContentBottom + 1),
        reason: reason,
      );
    }
  });
}
