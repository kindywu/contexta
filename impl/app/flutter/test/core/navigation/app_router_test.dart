import 'package:contexta/core/components/bottom_nav_bar.dart';
import 'package:contexta/core/navigation/app_router.dart';
import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/core/theme/app_colors.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/data/remote/llm_api.dart';
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
import 'package:drift/native.dart';
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

class _FakeLlmApi implements LlmApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// TTS 桩：reading/settings 页会 watch ttsEngineProvider，真实工厂在测试
/// 环境会残留 Timer（"A Timer is still pending"）。
class _TtsStub implements TtsEngine {
  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) => 'id';

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnParagraphStarted(
    void Function(String? utteranceId, int paragraphIndex, int total)?
        callback,
  ) {}
}

void main() {
  late GoRouter router;

  setUp(() {
    router = buildRouter();
  });

  /// 用指定 [r] 挂载 App（默认用 setUp 里的 router）。
  Future<void> pumpWith(WidgetTester tester, GoRouter r) async {
    // HomeScreen 的启动编排链（startupOrchestrationUseCase → syncArticles
    // UseCase）直接对 databaseProvider 取 requireValue：用内存库避免打开
    // 真实数据库。（空桩 settings 未引导 → 编排走 NeedsOnboarding 分支，
    // 不触发同步 / 网络。）
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        // HomeScreen 已接入（Task 22）：避免触达真实数据库 provider
        articleRepositoryProvider.overrideWithValue(_FakeArticleRepo()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
        statsRepositoryProvider.overrideWithValue(_FakeStatsRepo()),
        vocabularyRepositoryProvider.overrideWithValue(_FakeVocabRepo()),
        // Reading 查词（Task 24）：词库 + LLM 空桩
        wordRepositoryProvider.overrideWithValue(_FakeWordRepo()),
        llmApiProvider.overrideWithValue(_FakeLlmApi()),
        // reading/settings 页会 watch TTS：真实工厂在测试环境残留 Timer
        ttsEngineProvider.overrideWith((ref) async => _TtsStub()),
      ],
      child: MaterialApp.router(routerConfig: r),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) => pumpWith(tester, router);

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

  group('启动落点（已引导跳过向导）', () {
    // 用户反馈：已登录（已引导）用户冷启动会闪一下向导页。原因是跳过动作
    // 原本在 OnboardingScreen 的 post-frame 回调里做异步查库——必然晚于首帧。
    // 修复后由 router redirect 在首帧前决定落点，向导页一次都不渲染。
    testWidgets('已引导 → 直接落 home，向导页不渲染', (tester) async {
      router = buildRouter(isOnboarded: () async => true);
      await pumpWith(tester, router);

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(stackLocations(), [Routes.home]);
    });

    testWidgets('未引导 → 落在向导页', (tester) async {
      router = buildRouter(isOnboarded: () async => false);
      await pumpWith(tester, router);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(stackLocations(), [Routes.onboarding]);
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
