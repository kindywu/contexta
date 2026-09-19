import 'package:contexta/core/components/app_badge.dart';
import 'package:contexta/core/components/app_button.dart';
import 'package:contexta/core/components/app_card.dart';
import 'package:contexta/core/components/app_modal.dart';
import 'package:contexta/core/components/app_top_bar.dart';
import 'package:contexta/core/components/bottom_nav_bar.dart';
import 'package:contexta/core/components/loading_indicator.dart';
import 'package:contexta/core/theme/app_colors.dart';
import 'package:contexta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 组件库测试：视觉规格（颜色/圆角/字号/文案）与交互（onClick/禁用）。
void main() {
  Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  group('AppButton', () {
    testWidgets('primary：珊瑚底 + OnPrimary 文字 + 点击回调', (tester) async {
      var clicked = false;
      await tester.pumpWidget(wrap(SizedBox(
        width: 200,
        child: AppButton(text: '开始学习', onClick: () => clicked = true),
      )));

      final material =
          tester.widget<Material>(find.byType(Material).first);
      expect(material.color, AppColors.primary);
      final text = tester.widget<Text>(find.text('开始学习'));
      expect(text.style?.color, AppColors.onPrimary);

      await tester.tap(find.text('开始学习'));
      expect(clicked, isTrue);
    });

    testWidgets('secondary：SurfaceCard 底 + Ink 文字', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 200,
        child: AppButton(
          text: '返回',
          onClick: () {},
          variant: AppButtonVariant.secondary,
        ),
      )));

      final material =
          tester.widget<Material>(find.byType(Material).first);
      expect(material.color, AppColors.surfaceCard);
      final text = tester.widget<Text>(find.text('返回'));
      expect(text.style?.color, AppColors.ink);
    });

    testWidgets('禁用：不触发点击，颜色为 PrimaryDisabled 40%', (tester) async {
      var clicked = false;
      await tester.pumpWidget(wrap(SizedBox(
        width: 200,
        child: AppButton(
          text: '下一步',
          onClick: () => clicked = true,
          enabled: false,
        ),
      )));

      await tester.tap(find.text('下一步'));
      expect(clicked, isFalse);
      final material =
          tester.widget<Material>(find.byType(Material).first);
      expect(material.color, AppColors.primaryDisabled.withValues(alpha: 0.4));
    });
  });

  group('AppBadge', () {
    testWidgets('默认：SurfaceSoft 底 + Muted 字（胶囊）', (tester) async {
      await tester.pumpWidget(wrap(const AppBadge('CET4')));

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.decoration, isA<BoxDecoration>());
      final deco = container.decoration! as BoxDecoration;
      expect(deco.color, AppColors.surfaceSoft);
      final text = tester.widget<Text>(find.text('CET4'));
      expect(text.style?.color, AppColors.muted);
    });

    testWidgets('coral：Primary 底 + OnPrimary 字', (tester) async {
      await tester.pumpWidget(wrap(const AppBadge('CET4',
          variant: AppBadgeVariant.coral)));

      final deco = tester
          .widget<Container>(find.byType(Container))
          .decoration! as BoxDecoration;
      expect(deco.color, AppColors.primary);
      expect(
        tester.widget<Text>(find.text('CET4')).style?.color,
        AppColors.onPrimary,
      );
    });

    testWidgets('green：Success 底 + OnPrimary 字', (tester) async {
      await tester.pumpWidget(wrap(const AppBadge('CET6',
          variant: AppBadgeVariant.green)));

      final deco = tester
          .widget<Container>(find.byType(Container))
          .decoration! as BoxDecoration;
      expect(deco.color, AppColors.success);
    });
  });

  group('AppCard', () {
    testWidgets('SurfaceCard 底 + 点击回调', (tester) async {
      var clicked = false;
      await tester.pumpWidget(wrap(AppCard(
        onClick: () => clicked = true,
        child: const Text('card'),
      )));

      final material =
          tester.widget<Material>(find.byType(Material).first);
      expect(material.color, AppColors.surfaceCard);
      await tester.tap(find.text('card'));
      expect(clicked, isTrue);
    });

    testWidgets('无 onClick 时点击不触发', (tester) async {
      var clicked = false;
      await tester.pumpWidget(wrap(AppCard(
        child: const Text('card'),
      )));

      await tester.tap(find.text('card'));
      expect(clicked, isFalse);
    });
  });

  group('AppModal', () {
    testWidgets('visible=true 渲染遮罩 + 内容；点击遮罩触发 onDismiss',
        (tester) async {
      var dismissed = false;
      await tester.pumpWidget(wrap(AppModal(
        visible: true,
        onDismiss: () => dismissed = true,
        child: const Text('弹窗内容'),
      )));

      expect(find.text('弹窗内容'), findsOneWidget);
      // 点击遮罩（弹窗外区域）
      await tester.tapAt(const Offset(10, 10));
      expect(dismissed, isTrue);
    });

    testWidgets('点击面板空白区不触发 onDismiss', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(wrap(SizedBox(
        width: 400,
        height: 600,
        child: AppModal(
          visible: true,
          onDismiss: () => dismissed = true,
          child: const SizedBox(width: 200, height: 200),
        ),
      )));

      // 面板中心（居中模式下 (200,300) = panel 中心）→ 不应关闭
      await tester.tapAt(const Offset(200, 300));
      expect(dismissed, isFalse);
    });

    testWidgets('visible=false 不可交互', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(wrap(AppModal(
        visible: false,
        onDismiss: () => dismissed = true,
        child: const Text('弹窗内容'),
      )));

      expect(find.text('弹窗内容'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      expect(dismissed, isFalse);
    });
  });

  group('BottomNavBar', () {
    testWidgets('4 个 tab + 选中态 Primary / 未选中 Muted + 切换回调',
        (tester) async {
      BottomNavTab? selected;
      await tester.pumpWidget(wrap(BottomNavBar(
        selectedTab: BottomNavTab.home,
        onTabSelected: (t) => selected = t,
      )));

      expect(find.text('首页'), findsOneWidget);
      expect(find.text('生词'), findsOneWidget);
      expect(find.text('参考'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);

      // 选中 tab 标签 Primary，未选中 Muted
      final homeText = tester.widget<Text>(find.text('首页'));
      expect(homeText.style?.color, AppColors.primary);
      final vocabText = tester.widget<Text>(find.text('生词'));
      expect(vocabText.style?.color, AppColors.muted);

      await tester.tap(find.text('设置'));
      expect(selected, BottomNavTab.settings);
    });
  });

  group('LoadingIndicator / EmptyState', () {
    testWidgets('加载指示：珊瑚 spinner + 文案', (tester) async {
      await tester.pumpWidget(wrap(const LoadingIndicator(
        message: '生成中…',
      )));

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.color, AppColors.primary);
      expect(find.text('生成中…'), findsOneWidget);
    });

    testWidgets('空状态：图标 + 标题 + 副文案', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(
        message: '暂无文章',
        subMessage: '去设置里调整',
      )));

      expect(find.text('暂无文章'), findsOneWidget);
      expect(find.text('去设置里调整'), findsOneWidget);
    });
  });

  group('AppTopBar（左上角让位）', () {
    testWidgets('leadingInset 把返回键整体右推（平板避让系统窗口控件）',
        (tester) async {
      await tester.pumpWidget(wrap(Column(children: [
        AppTopBar(title: '录入单词', onBack: () {}, leadingInset: 0),
        AppTopBar(title: '录入单词', onBack: () {}, leadingInset: 96),
      ])));

      final bars = find.byType(AppTopBar);
      final back0 = find.descendant(of: bars.first, matching: find.byType(Icon));
      final back96 = find.descendant(of: bars.last, matching: find.byType(Icon));
      final dx0 = tester.getTopLeft(back0).dx;
      final dx96 = tester.getTopLeft(back96).dx;

      expect(dx96 - dx0, closeTo(96, 0.5));
    });

    testWidgets('默认（手机树）不加让位：leadingInset 缺省等价于 0', (tester) async {
      await tester.pumpWidget(wrap(Column(children: [
        AppTopBar(title: 'T', onBack: () {}),
        AppTopBar(title: 'T', onBack: () {}, leadingInset: 0),
      ])));
      final bars = find.byType(AppTopBar);
      double backDx(Finder bar) => tester
          .getTopLeft(find.descendant(of: bar, matching: find.byType(Icon)))
          .dx;
      expect(backDx(bars.first), backDx(bars.last));
    });
  });
}
