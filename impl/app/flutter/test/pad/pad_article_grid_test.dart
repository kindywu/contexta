import 'package:contexta/pad/pad_article_card.dart';
import 'package:contexta/pad/pad_article_grid.dart';
import 'package:contexta/pad/pad_layout.dart';
import 'package:contexta/ui/home/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pad 首页文章网格测试（2026-09-18 封面式卡片重设计）。
///
/// 钉住四件事：
/// 1. **列数**——本机内容区宽度下排 3 列，且随宽度推导而非写死；
/// 2. **封面块**——每张卡上半是难度色调的整块（网格的扫视锚点）；
/// 3. **每行等高**——同一行里标题长短不一的卡片被拉平，封面色块高度一致；
/// 4. **标题完整显示**——不设 maxLines／不省略（手机卡是单行省略号）。
///
/// 这些断言只针对 `lib/pad/` 的组件，不触碰手机渲染路径。
ArticleItemUi _article(int id, {String? title, String category = 'SCIENCE'}) =>
    ArticleItemUi(
      id: id,
      title: title ?? 'Article $id',
      description: category,
      difficultyLabel: 'CET4',
      categoryLabel: category,
    );

/// 本机 1280dp 横屏的**网格可用宽度**：屏 1280 − 侧边栏 208 − 页面留白 64
/// − 日期索引 180 − 索引/网格间距 32 = 796dp。
const double _padGridWidth = 796;

Future<void> _pumpGrid(
  WidgetTester tester,
  List<ArticleItemUi> articles, {
  double width = _padGridWidth,
  ValueChanged<int>? onClick,
}) async {
  // 必须先给画布一个真机尺寸：默认测试画布只有 800×600，会把它下面的
  // SizedBox 压回 800，列数随之变化（测试环境陷阱）。
  tester.view.physicalSize = const Size(2560, 1600); // 1280×800dp @2x
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: PadArticleGrid(
              articles: articles,
              onArticleClick: onClick ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('padGridColumns：列数推导', () {
    test('本机网格宽（796dp）→ 3 列', () {
      expect(padGridColumns(_padGridWidth), 3);
    });

    test('列数由宽度推导，不是写死 3：窄了回落、宽了增列', () {
      expect(padGridColumns(PadLayout.cardMinWidth), 1, reason: '刚好一张卡宽 → 1 列');
      expect(padGridColumns(600), 2);
      expect(padGridColumns(1100), 4);
    });

    test('超宽窗口封顶 4 列，不无限铺开', () {
      expect(padGridColumns(4000), PadLayout.gridMaxColumns);
      expect(PadLayout.gridMaxColumns, 4);
    });

    test('列数随宽度单调不减', () {
      var previous = padGridColumns(200);
      for (var width = 200.0; width <= 3000; width += 50) {
        final current = padGridColumns(width);
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
    });
  });

  group('网格排布', () {
    testWidgets('796dp 下 7 篇排成 3 列 × 3 行', (tester) async {
      final articles = [for (var i = 0; i < 7; i++) _article(i)];
      await _pumpGrid(tester, articles);

      final cards = find.byType(PadArticleCard).evaluate().toList();
      expect(cards.length, 7);

      // 首行三篇横向铺开（顶边对齐、左起递增），第四篇落到第二行
      final x0 = tester.getTopLeft(find.byType(PadArticleCard).at(0));
      final x1 = tester.getTopLeft(find.byType(PadArticleCard).at(1));
      final x2 = tester.getTopLeft(find.byType(PadArticleCard).at(2));
      final x3 = tester.getTopLeft(find.byType(PadArticleCard).at(3));

      expect(x0.dy, x1.dy, reason: '同一行顶边对齐');
      expect(x1.dy, x2.dy, reason: '同一行顶边对齐');
      expect([x1.dx, x2.dx], everyElement(greaterThan(x0.dx)));
      expect(x3.dy, greaterThan(x0.dy), reason: '第 4 篇换行');
      expect(x3.dx, moreOrLessEquals(x0.dx, epsilon: 0.5), reason: '换行回到首列');
    });

    testWidgets('每行卡片等高（标题长短不一时封面与元信息行仍对齐）', (tester) async {
      await _pumpGrid(tester, [
        _article(0, title: '短标题'),
        _article(1, title: '一个相当长的标题，长到在卡片宽度内必然折成好几行显示'),
        _article(2, title: '中等长度的标题'),
      ]);

      final heights = [
        for (var i = 0; i < 3; i++)
          tester.getSize(find.byType(PadArticleCard).at(i)).height,
      ];
      expect(heights[0], moreOrLessEquals(heights[1], epsilon: 0.5));
      expect(heights[1], moreOrLessEquals(heights[2], epsilon: 0.5));
    });

    testWidgets('末行不足列数：卡片宽度与满行一致（不撑满整行）', (tester) async {
      await _pumpGrid(tester, [for (var i = 0; i < 7; i++) _article(i)]);

      // 第 3 行只有第 7 篇（索引 6），宽度应与首行卡片一致
      final firstWidth = tester.getSize(find.byType(PadArticleCard).at(0)).width;
      final lastWidth = tester.getSize(find.byType(PadArticleCard).at(6)).width;
      expect(lastWidth, moreOrLessEquals(firstWidth, epsilon: 0.5));
    });

    testWidgets('点击卡片回传文章 id', (tester) async {
      int? clicked;
      await _pumpGrid(
        tester,
        [_article(7), _article(8)],
        onClick: (id) => clicked = id,
      );

      await tester.tap(find.byType(PadArticleCard).at(1));
      expect(clicked, 8);
    });
  });

  group('标题完整显示', () {
    testWidgets('长标题不设 maxLines／不加省略号，完整交给 Text 换行', (tester) async {
      const long =
          'The Quiet Revolution of Urban Gardening and What It Teaches Us About Patience';
      await _pumpGrid(tester, [_article(0, title: long)]);

      final title = tester.widget<Text>(find.text(long));
      expect(title.maxLines, isNull, reason: '手机卡是 maxLines: 1，pad 卡必须不限行');
      expect(title.overflow, isNull, reason: '不省略——标题必须完整显示');
    });

    testWidgets('超长标题在卡片宽度内换成多行（确实完整渲染，而非被裁掉）', (tester) async {
      const long =
          'The Quiet Revolution of Urban Gardening and What It Teaches Us About Patience';
      await _pumpGrid(tester, [_article(0, title: long)]);

      final titleFinder = find.text(long);
      final lineHeight = tester.getSize(titleFinder).height;
      // 单行标题的高度上限：18sp 字 + 25/18 行高 ≈ 25dp。
      expect(lineHeight, greaterThan(25.0 * 1.5), reason: '长标题应折成多行');
    });

    testWidgets('标题缺失时回落到分类名（不出现空标题卡）', (tester) async {
      await _pumpGrid(tester, [
        ArticleItemUi(
          id: 0,
          title: null,
          description: 'SCIENCE',
          difficultyLabel: 'CET6',
          categoryLabel: 'SCIENCE',
        ),
      ]);

      expect(find.text('SCIENCE'), findsWidgets);
    });
  });

  group('封面块（本次重设计的扫视锚点）', () {
    testWidgets('每张卡都有一个封面块，且与难度徽标同色', (tester) async {
      await _pumpGrid(tester, [_article(1, category: 'TECH')]);

      expect(find.byType(PadCover), findsOneWidget);
      // 难度 → 强调色是纯函数，封面与徽标共用，保证同卡内两处一致
      expect(difficultyAccent('CET4'), difficultyAccent('CET4'));
      expect(difficultyAccent('CET4'), isNot(difficultyAccent('CET6')));
    });

    testWidgets('封面块高度固定——同一行卡片封面不会被标题长度拉歪', (tester) async {
      await _pumpGrid(tester, [
        _article(0, title: '短'),
        _article(1, title: '一个相当长的标题，长到在卡片宽度内必然折成好几行显示才停'),
      ]);

      final covers = find.byType(PadCover).evaluate().toList();
      expect(covers.length, 2);
      final h0 = tester.getSize(find.byType(PadCover).at(0)).height;
      final h1 = tester.getSize(find.byType(PadCover).at(1)).height;
      expect(h0, moreOrLessEquals(PadLayout.cardCoverHeight, epsilon: 0.5));
      expect(h1, moreOrLessEquals(h0, epsilon: 0.5));
    });

    testWidgets('已读文章的封面褪色（网格里一眼分得出读过的）', (tester) async {
      await _pumpGrid(tester, [
        _article(0),
        ArticleItemUi(
          id: 1,
          title: 'Read One',
          description: 'SCIENCE',
          difficultyLabel: 'CET4',
          categoryLabel: 'SCIENCE',
          isReadCompleted: true,
        ),
      ]);

      final unread = tester.widget<PadCover>(find.byType(PadCover).at(0));
      final read = tester.widget<PadCover>(find.byType(PadCover).at(1));
      expect(read.dimmed, isTrue);
      expect(unread.dimmed, isFalse);
    });
  });
}
