import 'package:contexta/domain/app_info_provider.dart';
import 'package:contexta/domain/developer_alert_sender.dart';
import 'package:contexta/domain/error/app_error.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/daily_learning_info.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/resend_pending_alerts_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对照 Kotlin ResendPendingAlertsUseCaseTest.kt 移植（8 个用例）。

class FakeArticleRepository implements ArticleRepository {
  List<GenerationError> unnotifiedErrors = [];
  List<ArticleBatch> unnotifiedBatches = [];
  Article? articleView;
  List<Article> batchArticles = [];
  final List<int> markedErrorNotified = [];
  final List<int> markedBatchReadyNotified = [];

  @override
  Future<List<GenerationError>> getUnnotifiedErrors(String createdAfter) async =>
      unnotifiedErrors;

  @override
  Future<List<ArticleBatch>> getReadyBatchesUnnotified() async =>
      unnotifiedBatches;

  @override
  Future<Article?> getArticle(int articleId) async => articleView;

  @override
  Future<List<Article>> getArticles(int batchId) async => batchArticles;

  @override
  Future<void> markErrorNotified(int errorLogId) async {
    markedErrorNotified.add(errorLogId);
  }

  @override
  Future<void> markBatchReadyNotified(int batchId) async {
    markedBatchReadyNotified.add(batchId);
  }

  @override
  Stream<List<Article>> observeArticles(int batchId) =>
      throw UnimplementedError();

  @override
  Future<bool> isPipelineBlocked() => throw UnimplementedError();

  @override
  Future<bool> recoverIfNewerVersion(int currentVersionCode) =>
      throw UnimplementedError();

  @override
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
          String difficulty, String date) =>
      throw UnimplementedError();

  @override
  Future<ArticleBatch?> findNextReadyBatch(String difficulty, String? afterDate) =>
      throw UnimplementedError();

  @override
  Future<List<ArticleBatch>> getUnassignedReadyBatches(
          String difficulty, String? minGeneratedOn) =>
      throw UnimplementedError();

  @override
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate) =>
      throw UnimplementedError();

  @override
  Future<List<DailyLearningInfo>> getAllDailyLearningInfos() =>
      throw UnimplementedError();

  @override
  Future<String?> getMaxRefBatchDate() => throw UnimplementedError();

  @override
  Future<bool> assignBatchForToday(
          int batchId, String refBatchDate, int dailyCount) =>
      throw UnimplementedError();

  @override
  Future<int> createBatch(String difficulty, {String? generatedOn}) =>
      throw UnimplementedError();

  @override
  Future<void> createArticles(int batchId, List<String> categories) =>
      throw UnimplementedError();

  @override
  Future<bool> claimBatch(int batchId) => throw UnimplementedError();

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
  Future<ArticleBatch?> getBatchById(int batchId) =>
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
  Future<void> reconcileOrphanArticles() => throw UnimplementedError();

  @override
  Future<List<ArticleBatch>> getGeneratingBatches() =>
      throw UnimplementedError();

  @override
  Stream<List<GenerationError>> observeGenerationErrors() =>
      throw UnimplementedError();

  @override
  Future<void> resetArticleForRetry(int articleId) =>
      throw UnimplementedError();
}

class FakeAlertSender implements DeveloperAlertSender {
  bool sendResult = true;
  final List<String> articleFailures = [];
  final List<ErrorContext> articleContexts = [];
  final List<ErrorContext> structuralContexts = [];
  int llmFatalCalls = 0;
  int structuralCalls = 0;
  final List<({int batchId, int articleCount, String? generatedOn, String? difficulty})>
      batchReadies = [];

  @override
  Future<bool> sendLlmFatalError(LlmFatal error, ErrorContext context) async {
    llmFatalCalls++;
    return sendResult;
  }

  @override
  Future<bool> sendStructuralError(Structural error, ErrorContext context) async {
    structuralCalls++;
    structuralContexts.add(context);
    return sendResult;
  }

  @override
  Future<bool> sendArticleFailure({
    required String status,
    required String errorCode,
    required String errorMessage,
    required ErrorContext context,
  }) async {
    articleFailures.add('$status:$errorCode');
    articleContexts.add(context);
    return sendResult;
  }

  @override
  Future<bool> sendBatchReady({
    required int batchId,
    required int articleCount,
    required String? batchGeneratedOn,
    required String? batchDifficulty,
    required ErrorContext context,
  }) async {
    batchReadies.add((
      batchId: batchId,
      articleCount: articleCount,
      generatedOn: batchGeneratedOn,
      difficulty: batchDifficulty,
    ));
    return sendResult;
  }
}

GenerationError _error(
  int id,
  int entityId,
  String entityType,
  String code,
  String message,
) =>
    GenerationError(
      id: id,
      entityId: entityId,
      entityType: entityType,
      errorCode: code,
      errorMessage: message,
      errorHelp: null,
      retryCount: 0,
      createdAt: '2026-08-02T09:34:29+08:00',
    );

ArticleBatch _batch(int id, {String difficulty = 'HIGH', String? generatedOn}) =>
    ArticleBatch(
      id: id,
      status: BatchStatus.ready,
      difficultyLevelSnapshot: difficulty,
      generatedOn: generatedOn,
      lastUpdatedAt: '2026-08-02T10:05:03+08:00',
    );

void main() {
  late FakeArticleRepository repo;
  late FakeAlertSender alerts;
  late ResendPendingAlertsUseCase useCase;

  setUp(() {
    repo = FakeArticleRepository();
    alerts = FakeAlertSender();
    useCase = ResendPendingAlertsUseCase(
      articleRepository: repo,
      alertSender: alerts,
      timeProvider: const FakeTimeProvider(),
      appInfo: const FakeAppInfoProvider(),
    );
  });

  test('没有未通知的错误和批次时 不发送任何告警', () async {
    await useCase();

    expect(alerts.articleFailures, isEmpty);
    expect(alerts.batchReadies, isEmpty);
  });

  test('未通知的 ARTICLE 错误 补发 TIMEOUT 告警并回写标记', () async {
    repo.unnotifiedErrors = [
      _error(15, 42, 'ARTICLE', 'UNEXPECTED', 'Timed out waiting for 120000 ms'),
    ];
    repo.articleView = null;

    await useCase();

    expect(alerts.articleFailures, ['TIMEOUT:UNEXPECTED']);
    expect(alerts.articleContexts.single.articleId, 42);
    expect(alerts.articleContexts.single.batchId, isNull);
    expect(repo.markedErrorNotified, [15]);
  });

  test('LLM_RECOVERABLE_EXHAUSTED 错误补发 FAILED 告警', () async {
    repo.unnotifiedErrors = [
      _error(14, 24, 'ARTICLE', 'LLM_RECOVERABLE_EXHAUSTED',
          'LLM call failed after 3 retries'),
    ];
    repo.articleView = null;

    await useCase();

    expect(alerts.articleFailures, ['FAILED:LLM_RECOVERABLE_EXHAUSTED']);
    expect(repo.markedErrorNotified, [14]);
  });

  test('BATCH 类型错误补发结构性告警 并携带 batchId 上下文', () async {
    repo.unnotifiedErrors = [
      _error(16, 9, 'BATCH', 'STRUCTURAL_PIPELINE_BLOCKED', 'pipeline blocked'),
    ];

    await useCase();

    expect(alerts.structuralCalls, 1);
    expect(alerts.structuralContexts.single.batchId, 9);
    expect(alerts.structuralContexts.single.articleId, isNull);
    expect(repo.markedErrorNotified, [16]);
  });

  test('未通知的 READY 批次补发完成告警并回写标记', () async {
    repo.unnotifiedBatches = [_batch(9, generatedOn: '2026-08-02')];
    repo.batchArticles = List.generate(5, (i) => Article(
          id: i,
          batchId: 9,
          orderIndex: i,
          contentCategory: 'NEWS',
          title: null,
          status: ArticleStatus.success,
          generationStartedAt: null,
          generationCompletedAt: null,
          retryCount: 0,
          accumulatedReadSeconds: 0,
          readCompletedAt: null,
          lastRetryAt: null,
        ));

    await useCase();

    expect(alerts.batchReadies, hasLength(1));
    expect(alerts.batchReadies.single.batchId, 9);
    expect(alerts.batchReadies.single.articleCount, 5);
    expect(alerts.batchReadies.single.generatedOn, '2026-08-02');
    expect(alerts.batchReadies.single.difficulty, 'HIGH');
    expect(repo.markedBatchReadyNotified, [9]);
  });

  test('告警发送失败时不回写标记 下次启动继续补发', () async {
    repo.unnotifiedErrors = [
      _error(15, 42, 'ARTICLE', 'UNEXPECTED', 'Timed out'),
    ];
    repo.articleView = null;
    alerts.sendResult = false;

    await useCase();

    expect(repo.markedErrorNotified, isEmpty);
  });

  test('LLM_FATAL 错误补发致命告警', () async {
    repo.unnotifiedErrors = [
      _error(17, 50, 'ARTICLE', 'LLM_FATAL', 'auth failed'),
    ];
    repo.articleView = null;

    await useCase();

    expect(alerts.llmFatalCalls, 1);
    expect(repo.markedErrorNotified, [17]);
  });

  test('ARTICLE 错误带出所属批次的 batchId', () async {
    repo.unnotifiedErrors = [
      _error(18, 42, 'ARTICLE', 'UNEXPECTED', 'Timed out'),
    ];
    repo.articleView = Article(
      id: 42,
      batchId: 9,
      orderIndex: 1,
      contentCategory: 'NEWS',
      title: null,
      status: ArticleStatus.failed,
      generationStartedAt: null,
      generationCompletedAt: null,
      retryCount: 0,
      accumulatedReadSeconds: 0,
      readCompletedAt: null,
      lastRetryAt: null,
    );

    await useCase();

    expect(alerts.articleContexts.single.batchId, 9);
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

class FakeAppInfoProvider implements AppInfoProvider {
  const FakeAppInfoProvider();

  @override
  int get versionCode => 1;

  @override
  String get versionName => '1.0';

  @override
  String get deviceModel => 'Test Device';
}
