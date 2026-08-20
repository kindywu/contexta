import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';
import 'package:contexta/data/sync/sync_articles_usecase.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/startup_orchestration_usecase.dart';

/// 计划 B Task 5：启动编排（服务端同步模型）测试。
///
/// 语义（简报裁定）：
/// 1. 未 onboarding → StartupNeedsOnboarding（不触发同步）
/// 2. 已 onboarding + 无 token → StartupNeedsLogin（同步跳过，首页仍可用）
/// 3. 已 onboarding + 有 token → 同步执行 → 今天批次存在 → assignBatchForToday
///    （dailyCountSnapshot = settings.dailyArticleCount）→ Ready(syncedBatches: N)
/// 4. 已分配过（daily_learning 存在）→ 不重复分配
/// 5. 同步失败 → Ready(syncedBatches: 0)（不阻塞首页——历史文章可读）

/// ArticleRepository 桩：仅实现编排用到的 3 个方法，其余 noSuchMethod 兜底。
class FakeArticleRepository implements ArticleRepository {
  /// 今天已分配的批次（getAssignedBatchForDate 返回）。
  ArticleBatch? assignedToday;

  /// (难度, 今天) 批次（getBatchByDifficultyAndDate 返回）。
  ArticleBatch? todayBatch;

  final List<String> assignCalls = [];

  @override
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate) async =>
      assignedToday;

  @override
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
    String difficulty,
    String date,
  ) async => todayBatch;

  @override
  Future<bool> assignBatchForToday(
    int batchId,
    String refBatchDate,
    int dailyCount,
  ) async {
    assignCalls.add('$batchId:$refBatchDate:$dailyCount');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class FakeSettingsRepository implements SettingsRepository {
  UserSettings? settings = const UserSettings(
    isOnboarded: true,
    difficultyLevel: 'LOW',
    dailyArticleCount: 5,
  );

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// SyncArticlesUseCase 桩：记录调用次数，可配置结果 / 抛错。
class FakeSyncArticles extends SyncArticlesUseCase {
  FakeSyncArticles({
    this.result = const SyncResult(
      syncedBatches: 2,
      syncedArticles: 10,
      skippedAuth: false,
    ),
    this.throwError,
  }) : super(
         db: _db,
         batchDao: ArticleBatchDao(_db),
         articleDao: ArticleDao(_db),
         paragraphDao: ArticleParagraphDao(_db),
         fetchToday: () async => const [],
         timeProvider: const FakeTimeProvider(),
       );

  /// 只读的内存库（SyncArticlesUseCase 构造需要，本 fake 的 call 被覆写不走库）。
  static final _db = AppDatabase.forTesting(NativeDatabase.memory());

  final SyncResult result;
  Object? throwError;
  int calls = 0;

  @override
  Future<SyncResult> call() async {
    calls++;
    final e = throwError;
    if (e != null) throw e;
    return result;
  }
}

ArticleBatch _batch(
  int id,
  BatchStatus status, {
  String generatedOn = '2026-08-01',
}) => ArticleBatch(
  id: id,
  status: status,
  difficultyLevelSnapshot: 'LOW',
  generatedOn: generatedOn,
  lastUpdatedAt: '2026-08-01T21:25:42+08:00',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeArticleRepository repo;
  late FakeSettingsRepository settings;
  late FakeSyncArticles sync;
  late StartupOrchestrationUseCase useCase;

  setUp(() {
    repo = FakeArticleRepository();
    settings = FakeSettingsRepository();
    sync = FakeSyncArticles();
    useCase = StartupOrchestrationUseCase(
      articleRepository: repo,
      settingsRepository: settings,
      timeProvider: const FakeTimeProvider(),
      syncArticles: sync,
    );
  });

  // ─── 1. 未 onboarding → NeedsOnboarding（不触发同步） ─────────────────

  test('未 onboarding 返回 NeedsOnboarding 且不触发同步', () async {
    settings.settings = const UserSettings(
      isOnboarded: false,
      difficultyLevel: 'LOW',
      dailyArticleCount: 5,
      serverToken: 'tok',
    );

    final result = await useCase();

    expect(result, isA<StartupNeedsOnboarding>());
    expect(sync.calls, 0);
    expect(repo.assignCalls, isEmpty);
  });

  // ─── 2. 已 onboarding + 无 token → NeedsLogin（同步跳过） ─────────────

  test('无 token 返回 NeedsLogin 且同步跳过', () async {
    settings.settings = const UserSettings(
      isOnboarded: true,
      difficultyLevel: 'LOW',
      dailyArticleCount: 5,
      serverToken: null,
    );

    final result = await useCase();

    expect(result, isA<StartupNeedsLogin>());
    expect(sync.calls, 0);
    expect(repo.assignCalls, isEmpty);
  });

  test('token 为空字符串同样视为未登录', () async {
    settings.settings = const UserSettings(
      isOnboarded: true,
      difficultyLevel: 'LOW',
      dailyArticleCount: 5,
      serverToken: '',
    );

    final result = await useCase();

    expect(result, isA<StartupNeedsLogin>());
    expect(sync.calls, 0);
  });

  // ─── 3. 有 token → 同步 → 分配今天批次 → Ready ──────────────────────

  test(
    '同步成功 + 今天批次存在 → 分配给今天（dailyCountSnapshot=设置值）→ Ready(syncedBatches: N)',
    () async {
      settings.settings = const UserSettings(
        isOnboarded: true,
        difficultyLevel: 'LOW',
        dailyArticleCount: 5,
        serverToken: 'tok',
      );
      repo.todayBatch = _batch(
        3,
        BatchStatus.current,
        generatedOn: '2026-08-01',
      );

      final result = await useCase();

      expect(result, isA<StartupReady>());
      expect((result as StartupReady).syncedBatches, 2);
      expect(sync.calls, 1);
      expect(repo.assignCalls, ['3:2026-08-01:5']);
    },
  );

  test('同步成功但今天无对应难度的批次 → 不分配，仍 Ready', () async {
    settings.settings = const UserSettings(
      isOnboarded: true,
      difficultyLevel: 'LOW',
      dailyArticleCount: 5,
      serverToken: 'tok',
    );

    final result = await useCase();

    expect(result, isA<StartupReady>());
    expect((result as StartupReady).syncedBatches, 2);
    expect(repo.assignCalls, isEmpty);
  });

  // ─── 4. 今天已分配 → 不重复分配 ─────────────────────────────────────

  test('今天已有 daily_learning → 不重复分配，仍 Ready', () async {
    settings.settings = const UserSettings(
      isOnboarded: true,
      difficultyLevel: 'LOW',
      dailyArticleCount: 5,
      serverToken: 'tok',
    );
    repo.assignedToday = _batch(
      1,
      BatchStatus.ready,
      generatedOn: '2026-07-31',
    );
    repo.todayBatch = _batch(3, BatchStatus.current, generatedOn: '2026-08-01');

    final result = await useCase();

    expect(result, isA<StartupReady>());
    expect((result as StartupReady).syncedBatches, 2);
    expect(sync.calls, 1);
    expect(repo.assignCalls, isEmpty);
  });

  // ─── 5. 同步失败 → Ready(0)（不阻塞首页） ───────────────────────────

  test('同步失败 → Ready(syncedBatches: 0)，不阻塞首页', () async {
    settings.settings = const UserSettings(
      isOnboarded: true,
      difficultyLevel: 'LOW',
      dailyArticleCount: 5,
      serverToken: 'tok',
    );
    sync.throwError = StateError('network down');
    repo.todayBatch = _batch(3, BatchStatus.current, generatedOn: '2026-08-01');

    final result = await useCase();

    expect(result, isA<StartupReady>());
    expect((result as StartupReady).syncedBatches, 0);
    // 同步失败直接降级返回，不做分配
    expect(repo.assignCalls, isEmpty);
  });
}

class FakeTimeProvider implements TimeProvider {
  const FakeTimeProvider();

  @override
  int nowMillis() => 1785636000000;

  @override
  String nowDateTimeString() => '2026-08-01T12:00:00+08:00';

  @override
  String todayDateString() => '2026-08-01';

  @override
  String nextDateString() => '2026-08-02';
}
