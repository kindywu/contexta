import 'package:contexta/core/components/bottom_nav_bar.dart';
import 'package:contexta/core/navigation/app_router.dart';
import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 导航框架测试（对照 Kotlin NavGraph.kt / MainActivity.showBottomBar）：
/// - 初始路由 onboarding
/// - 底栏显隐：home/reference/settings 显示，vocabulary/reading/add_word 不显示
/// - tab 切换（context.go 等价 launchSingleTop）
/// - reading 入栈可 pop 返回；onboarding → home 清栈
void main() {
  late GoRouter router;

  setUp(() {
    router = buildRouter();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String path) async {
    router.go(path);
    await tester.pumpAndSettle();
  }

  List<String> stackLocations() => router.routerDelegate.currentConfiguration
      .matches
      .map((m) => m.matchedLocation)
      .toList();

  group('初始路由', () {
    testWidgets('启动落在 onboarding（占位页，无底栏）', (tester) async {
      await pumpApp(tester);

      expect(find.text('Onboarding — 待实现'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });
  });

  group('底栏显隐（对照 Kotlin showBottomBar）', () {
    testWidgets('home 显示底栏', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.home));

      expect(find.text('Home — 待实现'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('vocabulary 不显示底栏（Kotlin 对齐）', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.vocabulary));

      expect(find.text('Vocabulary — 待实现'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });

    testWidgets('reference / settings 显示底栏', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.reference));
      expect(find.byType(BottomNavBar), findsOneWidget);

      await go(tester, Routes.location(Routes.settings));
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('reading/:articleId 无底栏且解析参数', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.readingRoute(42));

      expect(find.text('Reading 42 — 待实现'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });

    testWidgets('add_word 无底栏', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.addWord));

      expect(find.text('AddWord — 待实现'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });
  });

  group('tab 切换', () {
    testWidgets('底栏点击切换到对应路由并更新选中态', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.home));

      await tester.tap(find.text('参考'));
      await tester.pumpAndSettle();

      expect(find.text('Reference — 待实现'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsOneWidget);
      // 选中 tab 文字 Primary，未选中 Muted
      expect(
        tester.widget<Text>(find.text('参考')).style?.color,
        AppColors.primary,
      );
      expect(
        tester.widget<Text>(find.text('首页')).style?.color,
        AppColors.muted,
      );
    });
  });

  group('返回与栈清理', () {
    testWidgets('reading 入栈后 pop 返回来源页', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.home));
      expect(stackLocations(), ['/home']);

      router.push(Routes.readingRoute(7));
      await tester.pumpAndSettle();
      expect(stackLocations(), ['/home', '/reading/7']);

      router.pop();
      await tester.pumpAndSettle();
      expect(stackLocations(), ['/home']);
      expect(find.text('Home — 待实现'), findsOneWidget);
    });

    testWidgets('onboarding → home 清栈（无 onboarding 残留）', (tester) async {
      await pumpApp(tester);
      expect(stackLocations(), ['/onboarding']);

      await go(tester, Routes.location(Routes.home));
      expect(stackLocations(), ['/home']);

      // 栈底不可再 pop（等价 Kotlin popUpTo inclusive：返回键不会回到
      // onboarding，而是退出 App）
      expect(router.canPop(), isFalse);
    });
  });
}
