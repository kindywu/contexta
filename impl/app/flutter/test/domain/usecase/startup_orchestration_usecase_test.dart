import 'package:contexta/domain/background_work_scheduler.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/daily_learning_info.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/resend_pending_alerts_usecase.dart';
import 'package:contexta/domain/usecase/startup_orchestration_usecase.dart';
import 'package:contexta/domain/usecase/trigger_next_batch_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对照 Kotlin StartupOrchestrationUseCaseTest.kt 移植（9 个用例）。

class FakeArticleRepository implements ArticleRepository {
  bool pipelineBlocked = false;
  bool recoverResult = true;
  List<ArticleBatch> generatingBatches = [];
  ArticleBatch? todayBatch;
  ArticleBatch? nextBatch;
  String? maxRefDate;
  final List<String> findCalls = [];
  final List<String> assignCalls = [];

  @override
  Future<bool> isPipelineBlocked() async => pipelineBlocked;

  @override
  Future<bool> recoverIfNewerVersion(int currentVersionCode) async =>
      recoverResult;

  @override
  Future<List<ArticleBatch>> getGeneratingBatches() async => generatingBatches;

  List<ArticleBatch> pendingBatches = [];

  @override
  Future<List<ArticleBatch>> getPendingBatches() async => pendingBatches;

  @override
  Future<void> reconcileOrphanArticles() async {}

  @override
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate) async =>
      todayBatch;

  @override
  Future<String?> getMaxRefBatchDate() async => maxRefDate;

  @override
  Future<ArticleBatch?> findNextReadyBatch(
      String difficulty, String? afterDate) async {
    findCalls.add('$difficulty:$afterDate');
    return nextBatch;
  }

  @override
  Future<bool> assignBatchForToday(
      int batchId, String refBatchDate, int dailyCount) async {
    assignCalls.add('$batchId:$refBatchDate:$dailyCount');
    return true;
  }

  @override
  Future<List<Article>> getArticles(int batchId) async => [];

  @override
  Stream<List<Article>> observeArticles(int batchId) =>
      throw UnimplementedError();

  @override
  Future<Article?> getArticle(int articleId) => throw UnimplementedError();

  @override
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
          String difficulty, String date) =>
      throw UnimplementedError();

  @override
  Future<List<ArticleBatch>> getUnassignedReadyBatches(
          String difficulty, String? minGeneratedOn) =>
      throw UnimplementedError();

  @override
  Future<List<DailyLearningInfo>> getAllDailyLearningInfos() =>
      throw UnimplementedError();

  @override
  Future<ArticleBatch?> getBatchById(int batchId) =>
      throw UnimplementedError();

  @override
  Future<bool> claimBatch(int batchId) => throw UnimplementedError();

  @override
  Future<int> createBatch(String difficulty, {String? generatedOn}) =>
      throw UnimplementedError();

  @override
  Future<void> createArticles(int batchId, List<String> categories) =>
      throw UnimplementedError();

  @override
  Future<bool> claimArticle(int articleId) => throw UnimplementedError();

  @override
  Future<void> completeArticle(
    int articleId,
    String title,
    List<ArticleParagraph> paragraphs, {
    required int retryCount,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> isBatchComplete(int batchId) => throw UnimplementedError();

  @override
  Future<bool> hasFatalArticle(int batchId) => throw UnimplementedError();

  @override
  Future<void> markBatchReady(int batchId) => throw UnimplementedError();

  @override
  Future<int?> markBatchBlocked(int batchId, String reason, int appVersionCode) =>
      throw UnimplementedError();

  @override
  Future<int?> failArticle(
    int articleId,
    String status, {
    String? errorCode,
    String? errorMessage,
    String? errorHelp,
    int retryCount = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<int?> fatalArticle(
    int articleId, {
    String? errorCode,
    String? errorMessage,
    int retryCount = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> markErrorNotified(int errorLogId) =>
      throw UnimplementedError();

  @override
  Future<void> markBatchReadyNotified(int batchId) =>
      throw UnimplementedError();

  @override
  Future<List<GenerationError>> getUnnotifiedErrors(String createdAfter) =>
      throw UnimplementedError();

  @override
  Future<List<ArticleBatch>> getReadyBatchesUnnotified() =>
      throw UnimplementedError();

  @override
  Future<void> addReadSeconds(int articleId, int deltaSeconds) =>
      throw UnimplementedError();

  @override
  Future<void> tryMarkReadCompleted(int articleId) =>
      throw UnimplementedError();

  @override
  Future<void> forceMarkReadCompleted(int articleId) =>
      throw UnimplementedError();

  @override
  Stream<List<GenerationError>> observeGenerationErrors() =>
      throw UnimplementedError();

  @override
  Future<void> resetArticleForRetry(int articleId) =>
      throw UnimplementedError();
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
  Stream<UserSettings?> observeSettings() => throw UnimplementedError();

  @override
  Future<bool> isOnboarded() => throw UnimplementedError();

  @override
  Future<void> completeOnboarding(String level, int dailyCount) =>
      throw UnimplementedError();

  @override
  Future<void> updateLevel(String level) => throw UnimplementedError();

  @override
  Future<bool> updateDailyArticleCount(int newCount) =>
      throw UnimplementedError();

  @override
  Future<void> updateTranslationMode(String mode) =>
      throw UnimplementedError();

  @override
  Future<void> updateTtsSpeed(double speed) =>
      throw UnimplementedError();

  @override
  Future<void> updateTtsVoice(TtsVoice voice) => throw UnimplementedError();

  @override
  Future<void> updateMasteryThreshold(int n) => throw UnimplementedError();

  @override
  Future<void> updateAutoPlayAudio(bool enabled) =>
      throw UnimplementedError();
}

class FakeTriggerNextBatch implements TriggerNextBatchUseCase {
  TriggerNextBatchUseCase? inner;
  final List<(String, int)> calls = [];
  Object? throwError;

  @override
  Future<void> call(String difficulty, int dailyCount) async {
    final e = throwError;
    if (e != null) throw e;
    calls.add((difficulty, dailyCount));
  }

  @override
  List<String> pickCategories(String difficulty) =>
      inner?.pickCategories(difficulty) ??
      (difficulty == 'LOW' ? ['DAILY_CONVERSATION'] : ['NEWS']);
}

class FakeGenerationScheduler implements BackgroundWorkScheduler {
  final List<int> scheduled = [];
  bool result = true;

  @override
  Future<bool> scheduleBatchGeneration(int batchId,
      {int appVersionCode = 0}) async {
    scheduled.add(batchId);
    return result;
  }

  @override
  Future<void> cancelBatchGeneration(int batchId) async {}

  @override
  Future<void> cancelAllGeneration() async {}
}

class FakeResendPendingAlerts implements ResendPendingAlertsUseCase {
  ResendPendingAlertsUseCase? inner;
  int calls = 0;
  Object? throwError;

  @override
  Future<void> call() async {
    calls++;
    final e = throwError;
    if (e != null) throw e;
  }
}

ArticleBatch _batch(int id, BatchStatus status,
        {String generatedOn = '2026-07-31'}) =>
    ArticleBatch(
      id: id,
      status: status,
      difficultyLevelSnapshot: 'LOW',
      generatedOn: generatedOn,
      lastUpdatedAt: '2026-07-31T21:25:42+08:00',
    );

void main() {
  late FakeArticleRepository repo;
  late FakeSettingsRepository settings;
  late FakeTriggerNextBatch trigger;
  late FakeGenerationScheduler scheduler;
  late FakeResendPendingAlerts resend;
  late StartupOrchestrationUseCase useCase;

  setUp(() {
    repo = FakeArticleRepository();
    settings = FakeSettingsRepository();
    trigger = FakeTriggerNextBatch();
    scheduler = FakeGenerationScheduler();
    resend = FakeResendPendingAlerts();
    useCase = StartupOrchestrationUseCase(
      articleRepository: repo,
      settingsRepository: settings,
      timeProvider: const FakeTimeProvider(),
      triggerNextBatch: trigger,
      generationScheduler: scheduler,
      resendPendingAlerts: resend,
    );
  });

  // ─── 修复核心：分配批次时传 maxRefDate，不回头选旧 seed 批次 ───────────

  test('未分配时 findNextReadyBatch 收到 maxRefDate 而不是 null', () async {
    repo.todayBatch = null;
    repo.maxRefDate = '2026-03-29';
    repo.nextBatch = null;

    final result = await useCase(1);

    // 关键断言：afterDate 必须是 maxRefDate（严格晚于已消费批次），
    // 否则会回头选 seed 旧批次
    expect(repo.findCalls, ['LOW:2026-03-29']);
    expect(result, isA<StartupNeedsInitialBatch>());
  });

  test('maxRefDate 之后有 READY 批次时分配给今天并触发前置生成', () async {
    repo.todayBatch = null;
    repo.maxRefDate = '2026-03-29';
    repo.nextBatch = _batch(6, BatchStatus.ready, generatedOn: '2026-07-31');

    final result = await useCase(1);

    expect(result, isA<StartupReady>());
    expect(repo.assignCalls, ['6:2026-07-31:5']);
    expect(trigger.calls, [('LOW', 5)]);
  });

  test('今天已分配时只触发前置生成 不重新查找批次', () async {
    repo.todayBatch = _batch(1, BatchStatus.ready, generatedOn: '2026-03-29');

    final result = await useCase(1);

    expect(result, isA<StartupReady>());
    expect(trigger.calls, [('LOW', 5)]);
    expect(repo.findCalls, isEmpty);
  });

  // ─── 无可用批次 → NeedsInitialBatch ─────────────────────────────────

  test('maxRefDate 之后无 READY 批次时返回 NeedsInitialBatch', () async {
    repo.todayBatch = null;
    repo.maxRefDate = '2026-07-31';
    repo.nextBatch = null;

    final result = await useCase(1);

    final needs = result as StartupNeedsInitialBatch;
    expect(needs.difficulty, 'LOW');
    expect(needs.dailyCount, 5);
    expect(trigger.calls, isEmpty);
  });

  // ─── 卡死批次重新调度 ───────────────────────────────────────────────

  test('GENERATING 批次在 reconcile 后被重新调度', () async {
    repo.generatingBatches = [_batch(6, BatchStatus.generating)];
    repo.todayBatch = null;
    repo.maxRefDate = '2026-07-31';
    repo.nextBatch = null;

    await useCase(1);

    expect(scheduler.scheduled, [6]);
  });

  test('PENDING 批次（worker 调度失败遗留）也被重新调度', () async {
    // Flutter 特有：worker 调度失败时批次永久卡 PENDING（Kotlin 版
    // worker 入队总是成功，无此问题），启动时一并重新入队。
    repo.pendingBatches = [_batch(7, BatchStatus.pending)];
    repo.generatingBatches = [_batch(8, BatchStatus.generating)];
    repo.todayBatch = null;
    repo.maxRefDate = '2026-07-31';
    repo.nextBatch = null;

    await useCase(1);

    // 先重调度 GENERATING（stuck），再重调度 PENDING
    expect(scheduler.scheduled, [8, 7]);
  });

  // ─── 未送达告警补发 ─────────────────────────────────────────────────

  test('启动时补发未送达的飞书告警', () async {
    repo.todayBatch = null;
    repo.maxRefDate = '2026-07-31';
    repo.nextBatch = null;

    await useCase(1);

    expect(resend.calls, 1);
  });

  test('补发告警失败不影响启动主流程', () async {
    resend.throwError = StateError('webhook down');
    repo.todayBatch = null;
    repo.maxRefDate = '2026-07-31';
    repo.nextBatch = null;

    final result = await useCase(1);

    // 补发失败被吞掉，启动编排照常完成
    expect(result, isA<StartupNeedsInitialBatch>());
  });

  // ─── 管道阻塞 ────────────────────────────────────────────────────────

  test('管道阻塞且版本未更新时返回 PipelineBlocked', () async {
    repo.pipelineBlocked = true;
    repo.recoverResult = false;

    final result = await useCase(1);

    expect(result, isA<StartupPipelineBlocked>());
  });

  test('管道阻塞但版本已更新时恢复正常流程', () async {
    repo.pipelineBlocked = true;
    repo.recoverResult = true;
    repo.todayBatch = null;
    repo.maxRefDate = '2026-07-31';
    repo.nextBatch = null;

    final result = await useCase(2);

    expect(result, isA<StartupNeedsInitialBatch>());
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
}
