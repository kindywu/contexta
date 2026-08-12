import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/background_work_scheduler.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/daily_learning_info.dart';
import 'package:contexta/domain/model/daily_stats.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/create_initial_batch_usecase.dart';
import 'package:contexta/domain/usecase/resend_pending_alerts_usecase.dart';
import 'package:contexta/domain/usecase/startup_orchestration_usecase.dart';
import 'package:contexta/domain/usecase/trigger_next_batch_usecase.dart';
import 'package:contexta/domain/app_info_provider.dart';
import 'package:contexta/domain/developer_alert_sender.dart';
import 'package:contexta/ui/home/home_controller.dart';
import 'package:contexta/ui/home/home_screen.dart';

/// Home 页测试（对照 Kotlin HomeViewModel/HomeScreen）：
/// - startupOrchestrate 各分支状态（Ready / NeedsInitialBatch / PipelineBlocked）
/// - 文章流按难度过滤 + 分组标签（今天/昨天/日期）
/// - streak 胶囊（streak>0 才显示）、点击文章 → onArticleClick
/// - 三态：加载 / 生成中 EmptyState / 空态

/// 记录调用并转发给 [handler] 的 ArticleRepository 桩。
class _FakeArticleRepo implements ArticleRepository {
  _FakeArticleRepo({
    this.onAllDailyLearningInfos,
    this.onObserveArticles,
  });

  final Future<List<DailyLearningInfo>> Function()? onAllDailyLearningInfos;
  final Stream<List<Article>> Function(int batchId)? onObserveArticles;

  @override
  Future<List<DailyLearningInfo>> getAllDailyLearningInfos() async {
    final handler = onAllDailyLearningInfos;
    if (handler != null) return handler();
    return const [];
  }

  @override
  Stream<List<Article>> observeArticles(int batchId) {
    final handler = onObserveArticles;
    if (handler != null) return handler(batchId);
    return const Stream.empty();
  }

  @override
  Stream<List<GenerationError>> observeGenerationErrors() =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #isPipelineBlocked) return Future.value(false);
    if (invocation.memberName == #getAssignedBatchForDate) {
      return Future.value(null);
    }
    if (invocation.memberName == #getSettings) return Future.value(null);
    if (invocation.memberName == #getGeneratingBatches) {
      return Future.value(<ArticleBatch>[]);
    }
    if (invocation.memberName == #findNextReadyBatch) {
      return Future.value(null);
    }
    return Future.value(null);
  }
}

class _FakeSettingsRepo implements SettingsRepository {
  const _FakeSettingsRepo();

  @override
  Future<UserSettings?> getSettings() async => const UserSettings(
        isOnboarded: true,
        difficultyLevel: 'MEDIUM',
        dailyArticleCount: 3,
      );

  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStatsRepo implements StatsRepository {
  _FakeStatsRepo({this.streak = 0});
  final int streak;

  @override
  Future<DailyStats?> getStats() async => DailyStats(
        totalArticlesRead: 0,
        totalWordsAdded: 0,
        totalWordsMastered: 0,
        totalLearningDays: streak > 0 ? 1 : 0,
        currentStreak: streak,
        longestStreak: streak,
        lastActiveDate: streak > 0 ? '2026-08-07' : null,
      );

  @override
  Stream<DailyStats?> observeStats() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// 可替换 call 的 StartupOrchestrationUseCase 桩（私有依赖传 stub 对象）。
class _StubStartupOrch extends StartupOrchestrationUseCase {
  _StubStartupOrch(this.result)
      : super(
          articleRepository: _noopRepository,
          settingsRepository: _noopSettings,
          timeProvider: _noopTime,
          triggerNextBatch: _noopTrigger,
          generationScheduler: _noopScheduler,
          resendPendingAlerts: _noopResend,
        );

  static final _noopRepository = _NoopArticleRepo();
  static final _noopSettings = _NoopSettingsRepo();
  static final _noopTime = _NoopTimeProvider();
  static final _noopTrigger = _NoopTriggerNextBatch();
  static final _noopScheduler = _NoopScheduler();
  static final _noopResend = _NoopResendAlerts();

  final StartupResult result;

  @override
  Future<StartupResult> call(int currentVersionCode) async => result;
}

class _StubCreateInitialBatch extends CreateInitialBatchUseCase {
  _StubCreateInitialBatch({this.onCall})
      : super(
          articleRepository: _noopRepository,
          triggerNextBatch: _noopTrigger,
          timeProvider: _noopTime,
        );

  static final _noopRepository = _NoopArticleRepo();
  static final _noopTrigger = _NoopTriggerNextBatch();
  static final _noopTime = _NoopTimeProvider();

  final Future<int> Function(String difficulty, int dailyCount)? onCall;

  @override
  Future<int> call(String difficulty, int dailyCount) =>
      onCall?.call(difficulty, dailyCount) ?? Future.value(-1);
}

class _RecordingScheduler implements BackgroundWorkScheduler {
  final List<int> scheduled = [];

  @override
  Future<bool> scheduleBatchGeneration(int batchId,
      {int appVersionCode = 0}) async {
    scheduled.add(batchId);
    return true;
  }

  @override
  Future<void> cancelBatchGeneration(int batchId) async {}

  @override
  Future<void> cancelAllGeneration() async {}
}

/// 各 use case 私有依赖的 no-op 桩。
class _NoopArticleRepo implements ArticleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _NoopSettingsRepo implements SettingsRepository {
  @override
  Future<UserSettings?> getSettings() async => null;

  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _NoopTimeProvider implements TimeProvider {
  @override
  int nowMillis() => 0;

  @override
  String nowDateTimeString() => '2026-08-07T12:00:00+08:00';

  @override
  String todayDateString() => '2026-08-07';

  @override
  String nextDateString() => '2026-08-02';

}

class _NoopTriggerNextBatch extends TriggerNextBatchUseCase {
  _NoopTriggerNextBatch()
      : super(
          articleRepository: _NoopArticleRepo(),
          generationScheduler: _NoopScheduler(),
          timeProvider: _NoopTimeProvider(),
        );

  @override
  Future<void> call(String difficulty, int dailyCount) async {}
}

class _NoopScheduler implements BackgroundWorkScheduler {
  @override
  Future<bool> scheduleBatchGeneration(int batchId,
      {int appVersionCode = 0}) async => true;

  @override
  Future<void> cancelBatchGeneration(int batchId) async {}

  @override
  Future<void> cancelAllGeneration() async {}
}

class _NoopResendAlerts extends ResendPendingAlertsUseCase {
  _NoopResendAlerts()
      : super(
          articleRepository: _NoopArticleRepo(),
          alertSender: _NoopAlertSender(),
          timeProvider: _NoopTimeProvider(),
          appInfo: _NoopAppInfo(),
        );

  @override
  Future<void> call() async {}
}

class _NoopAlertSender implements DeveloperAlertSender {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(true);
}

class _NoopAppInfo implements AppInfoProvider {
  @override
  int get versionCode => 1;

  @override
  String get versionName => '1.0';

  @override
  String get deviceModel => 'test';
}

Article makeArticle(int id, {String category = 'NEWS', String? title, String? readAt}) =>
    Article(
      id: id,
      batchId: 1,
      orderIndex: 0,
      contentCategory: category,
      title: title,
      status: ArticleStatus.success,
      generationStartedAt: null,
      generationCompletedAt: '2026-08-07T12:00:00+08:00',
      retryCount: 0,
      accumulatedReadSeconds: 0,
      readCompletedAt: readAt,
      lastRetryAt: null,
      maxRetries: 3,
      nextRetryAt: null,
      paragraphs: const [],
    );

/// 相对日期字符串（yyyy-MM-dd），daysAgo=0 为今天。
String dateStr(int daysAgo) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

DailyLearningInfo makeInfo(int daysAgo, int dailyCount) => DailyLearningInfo(
      learningDate: dateStr(daysAgo),
      dailyCountSnapshot: dailyCount,
      batch: ArticleBatch(
        id: 1,
        status: BatchStatus.ready,
        difficultyLevelSnapshot: 'MEDIUM',
        generatedOn: dateStr(daysAgo),
        lastUpdatedAt: '2026-08-07T12:00:00+08:00',
        blockedReason: null,
        blockedAt: null,
        articles: const [],
      ),
    );

void main() {
  late _FakeArticleRepo articleRepo;
  late _FakeStatsRepo statsRepo;
  late _RecordingScheduler scheduler;
  late StartupResult startupResult;
  String? createdDifficulty;
  int? createdDailyCount;
  int? articleClickId;

  setUp(() {
    articleRepo = _FakeArticleRepo();
    statsRepo = _FakeStatsRepo();
    scheduler = _RecordingScheduler();
    startupResult = const StartupReady();
    createdDifficulty = null;
    createdDailyCount = null;
    articleClickId = null;
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        articleRepositoryProvider.overrideWithValue(articleRepo),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
        statsRepositoryProvider.overrideWithValue(statsRepo),
        backgroundWorkSchedulerProvider.overrideWithValue(scheduler),
        startupOrchestrationUseCaseProvider
            .overrideWithValue(_StubStartupOrch(startupResult)),
        createInitialBatchUseCaseProvider.overrideWithValue(
          _StubCreateInitialBatch(onCall: (difficulty, dailyCount) async {
            createdDifficulty = difficulty;
            createdDailyCount = dailyCount;
            return 999;
          }),
        ),
      ],
    );
  }

  group('controller', () {
    test('Ready：加载完成，文章按难度过滤 + 今天分组 + streak 传递', () async {
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) => Stream.value([
          makeArticle(11, category: 'NEWS', title: '今日新闻'),
          makeArticle(12, category: 'SIMPLE_STORY', title: '简单故事'),
          makeArticle(13,
              category: 'NEWS', title: '新闻二', readAt: '2026-08-07T10:00:00+08:00'),
        ]),
      );
      statsRepo = _FakeStatsRepo(streak: 5);
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();
      // observeArticles 流事件在下一个事件循环投递
      await Future<void>.delayed(Duration.zero);

      final state = container.read(homeControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.streak, 5);
      // MEDIUM 过滤后 2 篇（SIMPLE_STORY 是 LOW 被滤掉）
      final group = state.articleGroups.single;
      expect(group.dateLabel, '今天');
      expect(group.articles.length, 2);
      expect(group.articles[0].isReadCompleted, isFalse);
      expect(group.articles[1].isReadCompleted, isTrue);
      expect(group.articles[0].description, 'NEWS');
      // difficultyLabel = CET4/CET6/专八 展示徽标（LOW/MEDIUM/HIGH 映射）
      expect(group.articles[0].difficultyLabel, 'CET6');
    });

    test('NeedsInitialBatch：创建批次 + 调度生成 + isGenerating', () async {
      startupResult = const StartupNeedsInitialBatch(
          difficulty: 'HIGH', dailyCount: 5);
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();

      expect(createdDifficulty, 'HIGH');
      expect(createdDailyCount, 5);
      expect(scheduler.scheduled, [999]);
      final state = container.read(homeControllerProvider);
      expect(state.isGenerating, isTrue);
      expect(state.generationMessage, '正在准备文章…');
    });

    test('PipelineBlocked：显示阻塞提示', () async {
      startupResult = const StartupPipelineBlocked();
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();

      final state = container.read(homeControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.generationMessage, '生成管道被阻塞，请联系技术支持');
    });

    test('今天组空但昨天组有文章 → isGenerating=true（生成中提示不静默）',
        () async {
      // 2026-08-12：worker 生成期间今天的组被过滤，昨天组存在时也必须
      // 显示"生成中"，避免今天静默缺失。
      final yesterdayInfo = DailyLearningInfo(
        learningDate: dateStr(1),
        dailyCountSnapshot: 3,
        batch: ArticleBatch(
          id: 2,
          status: BatchStatus.ready,
          difficultyLevelSnapshot: 'MEDIUM',
          generatedOn: dateStr(1),
          lastUpdatedAt: '2026-08-07T12:00:00+08:00',
          blockedReason: null,
          blockedAt: null,
          articles: const [],
        ),
      );
      articleRepo = _FakeArticleRepo(
        // 今天 + 昨天两条记录；今天批次（id=1）文章流为空（生成中）
        onAllDailyLearningInfos: () async => [makeInfo(0, 3), yesterdayInfo],
        onObserveArticles: (batchId) => Stream.value(
          batchId == 1
              ? const []
              : [makeArticle(21, category: 'NEWS', title: '昨天新闻')],
        ),
      );
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(homeControllerProvider);
      expect(state.isGenerating, isTrue);
      expect(state.generationMessage, '文章生成中，请稍候…');
      // 昨天的组仍然展示
      expect(state.articleGroups.any((g) => g.dateLabel == '昨天'), isTrue);
      expect(state.articleGroups.any((g) => g.dateLabel == '今天'), isFalse);
    });

    test('今天组有文章 → isGenerating=false', () async {
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(11, category: 'NEWS', title: '新闻')]),
      );
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(homeControllerProvider);
      expect(state.isGenerating, isFalse);
    });
  });

  group('UI', () {
    Future<void> pumpHome(WidgetTester tester, ProviderContainer container) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: HomeScreen(onArticleClick: (id) => articleClickId = id),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('生成中显示 EmptyState（文章生成中 + 文案）', (tester) async {
      startupResult = const StartupNeedsInitialBatch(
          difficulty: 'MEDIUM', dailyCount: 3);
      final container = makeContainer();
      await pumpHome(tester, container);

      expect(find.text('文章生成中'), findsOneWidget);
    });

    testWidgets('空态显示暂无文章', (tester) async {
      final container = makeContainer();
      await pumpHome(tester, container);

      expect(find.text('暂无文章'), findsOneWidget);
    });

    testWidgets('streak>0 显示胶囊', (tester) async {
      statsRepo = _FakeStatsRepo(streak: 3);
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(11, category: 'NEWS', title: '新闻')]),
      );
      final container = makeContainer();
      await pumpHome(tester, container);

      expect(find.text('连续 3 天'), findsOneWidget);
    });

    testWidgets('streak=0 不显示胶囊', (tester) async {
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(11, category: 'NEWS', title: '新闻')]),
      );
      final container = makeContainer();
      await pumpHome(tester, container);

      expect(find.textContaining('连续'), findsNothing);
    });

    testWidgets('点击文章卡片触发 onArticleClick', (tester) async {
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(11, category: 'NEWS', title: '今日新闻')]),
      );
      final container = makeContainer();
      await pumpHome(tester, container);

      await tester.tap(find.text('今日新闻'));
      expect(articleClickId, 11);
    });
  });
}
