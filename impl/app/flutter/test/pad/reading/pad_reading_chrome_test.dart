import 'package:contexta/pad/pad_layout.dart';
import 'package:contexta/pad/reading/pad_reading_chrome.dart';
import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 沉浸式阅读器工具栏测试（2026-09-18 重设计，同日实测后补常驻件）。
///
/// 守的是"沉浸"这条设计承诺：默认只有一条胶囊带 + 左上角一个返回圆键，
/// 其余控件都不出现。但**出口与朗读不能藏**——真机实测里读者找不到回家的路
/// 也没找到朗读，所以这两样必须常驻，哪怕牺牲一点沉浸感。
void main() {
  late PageController controller;

  setUp(() => controller = PageController());
  tearDown(() => controller.dispose());

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  Future<void> pumpPill(
    WidgetTester tester, {
    int totalPages = 345,
    bool isSpeaking = false,
    VoidCallback? onToggleChrome,
    VoidCallback? onTogglePlayback,
    TranslationMode translationMode = TranslationMode.full,
    VoidCallback? onCycleTranslationMode,
  }) => pump(
    tester,
    PadPagePill(
      pageController: controller,
      totalPages: totalPages,
      isSpeaking: isSpeaking,
      translationMode: translationMode,
      onToggleChrome: onToggleChrome ?? () {},
      onTogglePlayback: onTogglePlayback ?? () {},
      onCycleTranslationMode: onCycleTranslationMode ?? () {},
    ),
  );

  /// 胶囊 + 真实 PageView 的组合（生产里胶囊就是这么挂在书页上的）。
  /// 单挂胶囊无法 jumpToPage——PageController 没有 attach 到任何 PageView 时
  /// 会直接断言失败。
  Future<void> pumpPillOverPageView(
    WidgetTester tester, {
    required int pageCount,
    required int totalPages,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: pageCount,
                itemBuilder: (_, i) => Center(child: Text('spread \$i')),
              ),
            ),
            SizedBox(
              height: PadLayout.pagePillRowHeight,
              child: Center(
                child: PadPagePill(
                  pageController: controller,
                  totalPages: totalPages,
                  isSpeaking: false,
                  translationMode: TranslationMode.full,
                  onToggleChrome: () {},
                  onTogglePlayback: () {},
                  onCycleTranslationMode: () {},
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  group('页码胶囊（沉浸态唯一常驻控件）', () {
    testWidgets('显示「右页页号 / 总页数」', (tester) async {
      await pumpPill(tester, totalPages: 345);
      expect(find.text('2 / 345'), findsOneWidget);
    });

    testWidgets('点击胶囊唤出工具栏', (tester) async {
      var toggles = 0;
      await pumpPill(tester, onToggleChrome: () => toggles++);

      await tester.tap(find.text('2 / 345'));
      await tester.pumpAndSettle();

      expect(toggles, 1, reason: '胶囊是唯一的唤出入口，必须可点');
    });

    testWidgets('不朗读时常驻「朗读全文」入口（不再藏进底栏）', (tester) async {
      var playbackToggles = 0;
      await pumpPill(
        tester,
        isSpeaking: false,
        onTogglePlayback: () => playbackToggles++,
      );

      expect(find.text('朗读全文'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);
      expect(
        find.byType(Tooltip),
        findsNothing,
        reason: '入口靠文字自解释，不靠长按提示——长按在沉浸阅读里没人会做',
      );

      await tester.tap(find.text('朗读全文'));
      await tester.pumpAndSettle();
      expect(playbackToggles, 1);
    });

    testWidgets('朗读中同一个位置变暂停键——沉浸态下必须能停下来', (tester) async {
      var playbackToggles = 0;
      await pumpPill(
        tester,
        isSpeaking: true,
        onTogglePlayback: () => playbackToggles++,
      );

      expect(find.text('暂停'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.text('朗读全文'), findsNothing);

      await tester.tap(find.text('暂停'));
      await tester.pumpAndSettle();
      expect(playbackToggles, 1);
    });

    testWidgets('译文模式常驻在胶囊带，点一下循环到下一个模式', (tester) async {
      var cycles = 0;
      await pumpPill(
        tester,
        translationMode: TranslationMode.blurred,
        onCycleTranslationMode: () => cycles++,
      );

      expect(
        find.text('译文'),
        findsOneWidget,
        reason: '译文模式在平板上原本只在唤出态顶栏，读者找不到（2026-09-20 实测）',
      );
      expect(find.text('模糊'), findsOneWidget);

      await tester.tap(find.text('模糊'));
      await tester.pumpAndSettle();
      expect(cycles, 1);
    });

    testWidgets('随翻页实时更新页号', (tester) async {
      await pumpPillOverPageView(tester, pageCount: 5, totalPages: 10);
      expect(find.text('2 / 10'), findsOneWidget);

      controller.jumpToPage(2); // 第 3 跨页 → 右页 = 6
      await tester.pumpAndSettle();

      expect(find.text('6 / 10'), findsOneWidget);
    });

    testWidgets('最后一跨页：右页页号封顶在总页数（不显示超出）', (tester) async {
      // 3 页 = 2 跨页；第 2 跨页右页不存在，应封顶在 3 而不是 4
      await pumpPillOverPageView(tester, pageCount: 2, totalPages: 3);
      controller.jumpToPage(1);
      await tester.pumpAndSettle();

      expect(find.text('3 / 3'), findsOneWidget);
    });
  });

  group('沉浸态常驻返回键', () {
    testWidgets('是一个能点的返回箭头（收起态唯一可见的出口）', (tester) async {
      var backs = 0;
      await pump(
        tester,
        PadReadingFloatingBack(onBack: () => backs++),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(backs, 1);
    });

    testWidgets('触摸目标不小于 44dp', (tester) async {
      await pump(
        tester,
        PadReadingFloatingBack(onBack: () {}),
      );

      final size = tester.getSize(find.byType(InkWell));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('顶栏', () {
    testWidgets('显示返回 / 标题 / 译文模式；未读完不显示已读标记', (tester) async {
      var backs = 0;
      await pump(
        tester,
        PadReadingTopBar(
          title: 'The Future of Remote Work',
          translationMode: TranslationMode.blurred,
          isReadCompleted: false,
          onBack: () => backs++,
          onCycleTranslationMode: () {},
        ),
      );

      expect(find.text('The Future of Remote Work'), findsOneWidget);
      expect(find.text(TranslationMode.blurred.label), findsOneWidget);
      expect(find.text('✓ 已读'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(backs, 1);
    });

    testWidgets('已读完显示已读标记', (tester) async {
      await pump(
        tester,
        PadReadingTopBar(
          title: 'T',
          translationMode: TranslationMode.full,
          isReadCompleted: true,
          onBack: () {},
          onCycleTranslationMode: () {},
        ),
      );

      expect(find.text('✓ 已读'), findsOneWidget);
    });
  });

  group('底栏', () {
    Future<void> pumpBottom(
      WidgetTester tester, {
      double progress = 0.35,
      bool isSpeaking = false,
      double? speechProgress,
      int? speechTotal,
      VoidCallback? onCollapse,
    }) => pump(
      tester,
      PadReadingBottomBar(
        progress: progress,
        pageLabel: '12 / 345 页',
        isSpeaking: isSpeaking,
        ttsSpeed: 1.0,
        speechProgress: speechProgress,
        speechTotalSentences: speechTotal,
        onTogglePlayback: () {},
        onToggleTtsSpeed: () {},
        onCollapse: onCollapse ?? () {},
      ),
    );

    testWidgets('页码 + 百分比 + 朗读 + 语速', (tester) async {
      await pumpBottom(tester);

      expect(find.text('12 / 345 页'), findsOneWidget);
      expect(find.text('35%'), findsOneWidget);
      expect(find.text('朗读'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('朗读中按钮变「暂停」并显示句进度', (tester) async {
      await pumpBottom(
        tester,
        isSpeaking: true,
        speechProgress: 7,
        speechTotal: 42,
      );

      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('第 7/42 句'), findsOneWidget);
    });

    testWidgets('收起按钮可点（工具栏自己也能收）', (tester) async {
      var collapsed = 0;
      await pumpBottom(tester, onCollapse: () => collapsed++);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();
      expect(collapsed, 1);
    });
  });

  group('工具栏高度（分页几何的一部分）', () {
    test('底栏高度必须等于书页让出的那条带——否则唤出时会压住最后一行', () {
      // 这些常量被阅读页与分页器共同引用：书页高度 = 视口 − pagePillRowHeight。
      // 底栏是覆盖层，比让出的带更高就会盖住正文末行（读者眼睛所在的位置）。
      expect(
        PadLayout.pagePillRowHeight,
        PadLayout.chromeBottomBarHeight,
        reason: '底栏要正好铺满让出的那条带，不能溢出到正文上',
      );
      expect(PadLayout.chromeTopBarHeight, greaterThan(0));
    });

    test('让出的带足够放下一页正文（不是把屏幕吃掉）', () {
      // 800dp 高的平板上，让出 56dp 后正文还有约 700dp——仍能放 20+ 行。
      expect(PadLayout.pagePillRowHeight, lessThan(80));
    });
  });
}
