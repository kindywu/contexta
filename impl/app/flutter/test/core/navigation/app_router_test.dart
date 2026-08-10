import 'package:contexta/core/components/bottom_nav_bar.dart';
import 'package:contexta/core/navigation/app_router.dart';
import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/core/theme/app_colors.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/llm_client.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/ui/addword/add_word_screen.dart';
import 'package:contexta/ui/home/home_screen.dart';
import 'package:contexta/ui/onboarding/onboarding_screen.dart';
import 'package:contexta/ui/reading/reading_screen.dart';
import 'package:contexta/ui/reference/reference_screen.dart';
import 'package:contexta/ui/settings/settings_screen.dart';
import 'package:contexta/ui/vocabulary/vocabulary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 导航框架测试（对照 Kotlin NavGraph.kt / MainActivity.showBottomBar）：
/// - 初始路由 onboarding
/// - 底栏显隐：home/reference/settings 显示，vocabulary/reading/add_word 不显示
/// - tab 切换（context.go 等价 launchSingleTop）
/// - reading 入栈可 pop 返回；onboarding → home 清栈
///
/// Home 页已接入真实实现（Task 22）：用空桩仓储避免触达真实数据库。

class _FakeArticleRepo implements ArticleRepository {
  @override
  Future<bool> isPipelineBlocked() async => false;

  @override
  Stream<List<GenerationError>> observeGenerationErrors() =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  Future<UserSettings?> getSettings() async => null;

  @override
  Future<bool> isOnboarded() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStatsRepo implements StatsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// Reading 页（Task 23 接入）需要生词集合；空桩不触达数据库。
class _FakeVocabRepo implements VocabularyRepository {
  @override
  Future<List<VocabWord>> getActiveWords() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// Reading 页（Task 24 查词弹窗）新增词库 + LLM 依赖；空桩不触达数据库。
class _FakeWordRepo implements WordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeLlmClient implements LlmClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}
void main() {
  late GoRouter router;

  setUp(() {
    router = buildRouter();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // HomeScreen 已接入（Task 22）：避免触达真实数据库 provider
        articleRepositoryProvider.overrideWithValue(_FakeArticleRepo()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
        statsRepositoryProvider.overrideWithValue(_FakeStatsRepo()),
        vocabularyRepositoryProvider.overrideWithValue(_FakeVocabRepo()),
        // Reading 查词（Task 24）：词库 + LLM 空桩
        wordRepositoryProvider.overrideWithValue(_FakeWordRepo()),
        llmClientProvider.overrideWithValue(_FakeLlmClient()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
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
    testWidgets('启动落在 onboarding（真实页，无底栏）', (tester) async {
      await pumpApp(tester);

      // Task 29 修复：Onboarding 页已接入路由（Task 21 漏接）
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Contexta'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });
  });

  group('底栏显隐（对照 Kotlin showBottomBar）', () {
    testWidgets('home 显示底栏', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.home));

      // 真实 HomeScreen（Task 22 落地）：空桩仓储下落到空态
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('暂无文章'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('vocabulary 不显示底栏（Kotlin 对齐）', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.vocabulary));

      // 真实 VocabularyScreen（Task 25 落地）：空词表 → 空态
      expect(find.byType(VocabularyScreen), findsOneWidget);
      expect(find.text('生词表为空'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });

    testWidgets('reference / settings 显示底栏', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.reference));

      // 真实 ReferenceScreen（Task 28 落地）：字母表 tab 初始渲染
      expect(find.byType(ReferenceScreen), findsOneWidget);
      expect(find.text('字母表'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsOneWidget);

      // 真实 SettingsScreen（Task 26 落地）：空桩仓储 → 默认设置态
      await go(tester, Routes.location(Routes.settings));
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('学习设置'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('reading/:articleId 无底栏且解析参数', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.readingRoute(42));

      expect(find.byType(ReadingScreen), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });

    testWidgets('add_word 无底栏', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.addWord));

      // 真实 AddWordScreen（Task 27 落地）：输入态初始渲染
      expect(find.byType(AddWordScreen), findsOneWidget);
      expect(find.text('录入单词'), findsOneWidget);
      expect(find.text('生成释义并加入生词库'), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });
  });

  group('tab 切换', () {
    testWidgets('底栏点击切换到对应路由并更新选中态', (tester) async {
      await pumpApp(tester);
      await go(tester, Routes.location(Routes.home));

      await tester.tap(find.text('参考'));
      await tester.pumpAndSettle();

      expect(find.byType(ReferenceScreen), findsOneWidget);
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
      expect(find.byType(HomeScreen), findsOneWidget);
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
