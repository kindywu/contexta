import 'package:contexta/core/theme/app_type.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/ui/reading/pagination/article_paginator.dart';
import 'package:contexta/ui/reading/pagination/reading_block.dart';
import 'package:contexta/ui/reading/pagination/spread_reader.dart';
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
  var userDrags = 0;
  var tappedWords = <String>[];

  setUp(() {
    controller = PageController();
    spreadIndex = 0;
    userDrags = 0;
    tappedWords = [];
    keys.clear();
    textKeys.clear();
  });

  tearDown(() => controller.dispose());

  Future<void> pumpReaderWith(
    WidgetTester tester,
    PaginatedArticle paginated,
    List<ArticleParagraph> paragraphs,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpreadReader(
            paginated: paginated,
            pageController: controller,
            title: 'A Title',
            paragraphs: paragraphs,
            sentencesByParagraph: const [[], [], [], []],
            translationMode: TranslationMode.full,
            revealedParagraphs: const {},
            vocabularyWords: const {},
            speakingParagraphIndex: null,
            speakingSentenceIndex: null,
            isReadCompleted: false,
            paragraphKey: paragraphKey,
            paragraphTextKey: paragraphTextKey,
            onWordClick: tappedWords.add,
            onTranslationClick: (_) {},
            onPlayParagraph: (_) {},
            onMarkAsRead: () {},
            onSpreadChanged: (i) => spreadIndex = i,
            onUserDrag: () => userDrags++,
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

  testWidgets('点击右侧页边空白翻到下一跨页', (tester) async {
    // 视口 1600×813 逻辑像素（DPR=1）：跨页内容 1100 居中 → 左右页边各
    // (1600 − 1100) / 2 = 250，远大于 kEdgeTapMinWidth(24)，页边点击才启用。
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpReader(tester, fourPages());
    expect(tester.getSize(find.byType(SpreadReader)), const Size(1600, 813));

    await tester.tapAt(const Offset(1550, 400)); // 右侧页边（x ∈ [1350, 1600)）
    await tester.pumpAndSettle();

    expect(spreadIndex, 1);
    expect(userDrags, 0); // 页边点击是点按，不是拖动
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
    expect(userDrags, greaterThan(0)); // 手指拖动（程序化翻页不计）
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
  });

  testWidgets('真实分页结果渲染在页内不溢出：页被填满时末块底边不越页底', (tester) async {
    tester.view.physicalSize = const Size(1600, 813);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 阶段 1（量尺）：先渲染一次，量出页码行顶边。页内容盒高度 =
    // 页码行顶边 − 页底留白 − 页顶留白——它是分页器与渲染唯一共享的几何量，
    // 必须实测（硬编码会随字体度量/内边距漂移而悄悄失效）。
    await pumpReader(tester, fourPages());
    final indicatorTop = tester.getTopLeft(find.text('2 / 4')).dy;
    expect(indicatorTop, greaterThan(kPageTopPadding + kPageBottomPadding));
    final indicatorHeight = 813 - indicatorTop;

    // 视口 1600 → 跨页 1100 → 单页 (1100 − kSpreadGutter) / 2 = 530
    const pageWidth = 530.0;
    const fillerText = 'Pack the page tightly with words.';
    const fillerTranslation = '把页面填满。';
    const targetContentHeight = 420.0;

    final paginator = buildPaginator();
    double heightOf(ReadingBlock block) => paginator.heightOf(
      block,
      pageWidth: pageWidth,
      bodyTextScaler: TextScaler.noScaling,
      labelTextScaler: TextScaler.noScaling,
      translationMode: TranslationMode.full,
    );

    final titleHeight = heightOf(const TitleBlock('A Title'));
    final fillerHeight = heightOf(
      const ParagraphBlock(index: 0, englishText: fillerText, chineseTranslation: fillerTranslation),
    );

    // 页内容盒高度取「标题 + N 段」的整数倍：页被填到一丝不剩——任何测量/
    // 渲染漂移都会立刻变成 RenderFlex 溢出，这正是本测试要抓的失败模式。
    final fillerCount = ((targetContentHeight - titleHeight) / fillerHeight).ceil();
    final contentHeight = titleHeight + fillerCount * fillerHeight;
    expect(fillerCount, greaterThan(1));

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
          ParagraphBlock(index: i, englishText: fillerText, chineseTranslation: fillerTranslation),
      ],
      pageWidth: pageWidth,
      pageHeight: contentHeight,
      bodyTextScaler: TextScaler.noScaling,
      labelTextScaler: TextScaler.noScaling,
      translationMode: TranslationMode.full,
    );

    // 渲染高度 = 分页高度：页内容盒正好等于 contentHeight
    tester.view.physicalSize = Size(
      1600,
      contentHeight + indicatorHeight + kPageTopPadding + kPageBottomPadding,
    );
    await pumpReaderWith(tester, paginated, paragraphs);

    // 分页器把整篇装进了一页且填满（本测试的前提）
    expect(paginated.pages.length, 1);
    expect(paginated.pages.single.overflows, isFalse);
    expect(
      paginated.pages.single.usedHeight,
      greaterThan(contentHeight - 1),
      reason: '页须被填满——空页测不出测量/渲染漂移',
    );

    // 无 RenderFlex 溢出（页已填满，多布局一个像素就会在这里报错）
    expect(tester.takeException(), isNull);

    // 每个块的渲染高 == 分页器算出的块高（测量/渲染同源）
    for (var i = 0; i < fillerCount; i++) {
      expect(
        tester.getRect(find.byKey(paragraphKey(i))).height,
        closeTo(fillerHeight, 1),
        reason: '第 $i 段渲染高与分页器测量高不一致',
      );
    }

    // 左页最后一个块的底边落在页内容盒底边之内（容 1px 舍入）
    final lastBlock = paginated.pages.single.blocks.last as ParagraphBlock;
    final lastBlockBottom = tester
        .getRect(find.byKey(paragraphKey(lastBlock.index)))
        .bottom;
    final pageContentBottom =
        tester.getTopLeft(find.text('1 / 1')).dy - kPageBottomPadding;
    expect(lastBlockBottom, lessThanOrEqualTo(pageContentBottom + 1));
  });
}
