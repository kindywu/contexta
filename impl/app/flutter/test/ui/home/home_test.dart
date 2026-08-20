import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';
import 'package:contexta/data/sync/sync_articles_usecase.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/daily_learning_info.dart';
import 'package:contexta/domain/model/daily_stats.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/startup_orchestration_usecase.dart';
import 'package:contexta/ui/home/home_controller.dart';
import 'package:contexta/ui/home/home_screen.dart';

/// Home 页测试（计划 B Task 5 改造后）：
/// - startupOrchestrate 各分支状态（Ready / NeedsLogin / NeedsOnboarding）
/// - 文章流按难度过滤 + 分组标签（今天/昨天/日期）
/// - streak 胶囊（streak>0 才显示）、点击文章 → onArticleClick
/// - 三态：加载 / 生成中 EmptyState / 空态
/// - refresh()：重跑同步编排 + 重载；下拉刷新接线

/// 记录调用并转发给 [handler] 的 ArticleRepository 桩。
class _FakeArticleRepo implements ArticleRepository {
  _FakeArticleRepo({this.onAllDailyLearningInfos, this.onObserveArticles});

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
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getAssignedBatchForDate) {
      return Future.value(null);
    }
    if (invocation.memberName == #getSettings) return Future.value(null);
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

/// 可替换 call 的 StartupOrchestrationUseCase 桩（私有依赖传 stub 对象），
/// 记录调用次数（refresh 断言用）。
class _StubStartupOrch extends StartupOrchestrationUseCase {
  _StubStartupOrch(this.result)
    : super(
        articleRepository: _noopRepository,
        settingsRepository: _noopSettings,
        timeProvider: _noopTime,
        syncArticles: _noopSync,
      );

  static final _noopRepository = _NoopArticleRepo();
  static final _noopSettings = _NoopSettingsRepo();
  static final _noopTime = _NoopTimeProvider();
  static final _noopSync = _NoopSyncArticles();

  final StartupResult result;
  int calls = 0;

  @override
  Future<StartupResult> call() async {
    calls++;
    return result;
  }
}

/// SyncArticlesUseCase 桩（构造 StartupOrchestrationUseCase 私有依赖用，
/// call 被覆写为 no-op——编排结果由 _StubStartupOrch 直接给出）。
class _NoopSyncArticles extends SyncArticlesUseCase {
  _NoopSyncArticles()
    : super(
        db: _db,
        batchDao: ArticleBatchDao(_db),
        articleDao: ArticleDao(_db),
        paragraphDao: ArticleParagraphDao(_db),
        fetchToday: () async => const [],
        timeProvider: _NoopTimeProvider(),
      );

  static final _db = AppDatabase.forTesting(NativeDatabase.memory());

  @override
  Future<SyncResult> call() async =>
      const SyncResult(syncedBatches: 0, syncedArticles: 0, skippedAuth: false);
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

Article makeArticle(
  int id, {
  String category = 'NEWS',
  String? title,
  String? readAt,
}) => Article(
  id: id,
  batchId: 1,
  orderIndex: 0,
  contentCategory: category,
  title: title,
  status: ArticleStatus.success,
  accumulatedReadSeconds: 0,
  readCompletedAt: readAt,
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
    articles: const [],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeArticleRepo articleRepo;
  late _FakeStatsRepo statsRepo;
  late StartupResult startupResult;
  int? articleClickId;

  setUp(() {
    articleRepo = _FakeArticleRepo();
    statsRepo = _FakeStatsRepo();
    startupResult = const StartupReady(syncedBatches: 0);
    articleClickId = null;
  });

  ProviderContainer makeContainer({StartupOrchestrationUseCase? orch}) {
    return ProviderContainer(
      overrides: [
        articleRepositoryProvider.overrideWithValue(articleRepo),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
        statsRepositoryProvider.overrideWithValue(statsRepo),
        startupOrchestrationUseCaseProvider.overrideWithValue(
          orch ?? _StubStartupOrch(startupResult),
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
          makeArticle(
            13,
            category: 'NEWS',
            title: '新闻二',
            readAt: '2026-08-07T10:00:00+08:00',
          ),
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

    test('NeedsLogin：本地文章照常加载（横幅由 home_screen 按登录态显示）', () async {
      startupResult = const StartupNeedsLogin();
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
      expect(state.isLoading, isFalse);
      expect(state.articleGroups.single.articles.length, 1);
    });

    test('同步失败（Ready(0)）：历史文章仍可读，不阻塞首页', () async {
      startupResult = const StartupReady(syncedBatches: 0);
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(1, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(21, category: 'NEWS', title: '昨天新闻')]),
      );
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(homeControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.articleGroups.single.articles.single.title, '昨天新闻');
    });

    test('同步创建的 CURRENT 批次（T4 遗留验证）经 daily_learning 引用后首页可见', () async {
      // T4 同步复用/创建 (难度, 今天) 批次时 status=CURRENT（非本地生成管道的
      // READY）。首页取数路径 getAllDailyLearningInfos → observeArticles(batchId)
      // → GetHomeArticlesUseCase 均不校验批次状态，仅按 daily_learning.ref_batch_id
      // 取文章——这里用 CURRENT 批次锁定「批次状态不校验」语义，防止将来
      // 引入 findNextReadyBatch 式 READY-only 过滤破坏同步批次展示。
      final currentInfo = DailyLearningInfo(
        learningDate: dateStr(0),
        dailyCountSnapshot: 3,
        batch: ArticleBatch(
          id: 7,
          status: BatchStatus.current,
          difficultyLevelSnapshot: 'MEDIUM',
          generatedOn: dateStr(0),
          lastUpdatedAt: '2026-08-07T12:00:00+08:00',
          articles: const [],
        ),
      );
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [currentInfo],
        onObserveArticles: (batchId) => Stream.value(
          batchId == 7
              ? [makeArticle(31, category: 'NEWS', title: '同步批次文章')]
              : const [],
        ),
      );
      final container = makeContainer();
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(homeControllerProvider);
      expect(state.articleGroups.single.articles.single.title, '同步批次文章');
    });

    test('今天组空但昨天组有文章 → isGenerating=true（同步中提示不静默）', () async {
      // 2026-08-12：worker 生成期间今天的组被过滤，昨天组存在时也必须
      // 显示"同步中"，避免今天静默缺失。
      final yesterdayInfo = DailyLearningInfo(
        learningDate: dateStr(1),
        dailyCountSnapshot: 3,
        batch: ArticleBatch(
          id: 2,
          status: BatchStatus.ready,
          difficultyLevelSnapshot: 'MEDIUM',
          generatedOn: dateStr(1),
          lastUpdatedAt: '2026-08-07T12:00:00+08:00',
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
      expect(state.generationMessage, '文章同步中…');
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

    test('refresh：重跑同步编排 + 重载文章流', () async {
      final orch = _StubStartupOrch(const StartupReady(syncedBatches: 2));
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(11, category: 'NEWS', title: '刷新新闻')]),
      );
      final container = makeContainer(orch: orch);
      final controller = container.read(homeControllerProvider.notifier);
      await controller.load();
      expect(orch.calls, 1);

      await controller.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(orch.calls, 2);
      final state = container.read(homeControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.articleGroups.single.articles.single.title, '刷新新闻');
    });
  });

  group('UI', () {
    Future<void> pumpHome(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: HomeScreen(onArticleClick: (id) => articleClickId = id),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('今天已分配但文章为空 → 同步中 EmptyState', (tester) async {
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) => Stream.value(const []),
      );
      final container = makeContainer();
      await pumpHome(tester, container);

      expect(find.text('文章同步中'), findsOneWidget);
    });

    testWidgets('空态显示暂无文章 + 同步失败副文案（B-T5 carry）', (tester) async {
      final container = makeContainer();
      await pumpHome(tester, container);

      expect(find.text('暂无文章'), findsOneWidget);
      expect(find.text('暂时没有文章，下拉刷新试试'), findsOneWidget);
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

    testWidgets('下拉刷新触发 refresh（同步编排重跑 + 重载）', (tester) async {
      final orch = _StubStartupOrch(const StartupReady(syncedBatches: 1));
      articleRepo = _FakeArticleRepo(
        onAllDailyLearningInfos: () async => [makeInfo(0, 3)],
        onObserveArticles: (_) =>
            Stream.value([makeArticle(11, category: 'NEWS', title: '新闻')]),
      );
      final container = makeContainer(orch: orch);
      await pumpHome(tester, container);
      // pumpHome 内 load() 已触发一次
      expect(orch.calls, 1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      // RefreshIndicator 动画分阶段推进（对照 flutter 官方
      // refresh_indicator_test.dart 的模式）：滚动回弹 → 指示器进入 →
      // 指示器收起。pumpAndSettle 在指示器动画期间可能超时。
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(orch.calls, 2);
    });
  });
}
