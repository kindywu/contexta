import 'package:contexta/domain/app_info_provider.dart';
import 'package:contexta/domain/developer_alert_sender.dart';
import 'package:contexta/domain/error/app_error.dart';
import 'package:contexta/domain/error/llm_exceptions.dart';
import 'package:contexta/domain/error/pipeline_blocking_exception.dart';
import 'package:contexta/domain/llm_client.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/daily_learning_info.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/generate_articles_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对照 Kotlin GenerateArticlesUseCaseTest.kt 移植（9 个用例）。
///
/// Kotlin mockk 的宽松 mock 语义 → Dart 用记录式 fake：
/// 只实现用例用到的方法，其余抛 UnimplementedError（Dart implements 不强制实现）。

class FakeArticleRepository implements ArticleRepository {
  List<Article> articles = [];
  bool claimResult = true;
  bool hasFatal = false;
  bool batchComplete = false;
  ArticleBatch? batchView;
  int? nextErrorLogId = 100;

  int markBatchReadyCalls = 0;
  int markBatchReadyNotifiedCalls = 0;
  int markErrorNotifiedCalls = 0;
  final List<int> notifiedIds = [];
  final List<String> failArticles = [];
  final List<String> fatalArticles = [];
  final List<String> completedTitles = [];
  List<List<ArticleParagraph>> completedParagraphs = [];
  String? batchBlockedReason;

  @override
  Future<List<Article>> getArticles(int batchId) async => articles;

  @override
  Future<bool> claimArticle(int articleId) async => claimResult;

  @override
  Future<void> completeArticle(
    int articleId,
    String title,
    List<ArticleParagraph> paragraphs, {
    required int retryCount,
  }) async {
    completedTitles.add(title);
    completedParagraphs.add(paragraphs);
  }

  @override
  Future<bool> hasFatalArticle(int batchId) async => hasFatal;

  @override
  Future<bool> isBatchComplete(int batchId) async => batchComplete;

  @override
  Future<void> markBatchReady(int batchId) async {
    markBatchReadyCalls++;
  }

  @override
  Future<ArticleBatch?> getBatchById(int batchId) async => batchView;

  @override
  Future<void> markBatchReadyNotified(int batchId) async {
    markBatchReadyNotifiedCalls++;
  }

  @override
  Future<void> markErrorNotified(int errorLogId) async {
    markErrorNotifiedCalls++;
    notifiedIds.add(errorLogId);
  }

  @override
  Future<int?> failArticle(
    int articleId,
    String status, {
    String? errorCode,
    String? errorMessage,
    String? errorHelp,
    int retryCount = 0,
  }) async {
    failArticles.add('$articleId:$status:$errorCode');
    return nextErrorLogId;
  }

  @override
  Future<int?> fatalArticle(
    int articleId, {
    String? errorCode,
    String? errorMessage,
    int retryCount = 0,
  }) async {
    fatalArticles.add('$articleId:$errorCode');
    return nextErrorLogId;
  }

  @override
  Future<int?> markBatchBlocked(
      int batchId, String reason, int appVersionCode) async {
    batchBlockedReason = reason;
    return nextErrorLogId;
  }

  @override
  Stream<List<Article>> observeArticles(int batchId) =>
      throw UnimplementedError();

  @override
  Future<Article?> getArticle(int articleId) =>
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
  Future<ArticleBatch?> findNextReadyBatch(
          String difficulty, String? afterDate) =>
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

/// 记录式 LLM fake：按配置返回成功 / 抛指定异常。
class FakeLlmClient implements LlmClient {
  Object? throwError;
  String content = '<title>Test</title>'
      '<paragraph>Hello world</paragraph><translation>你好世界</translation>';

  int callCount = 0;

  @override
  Future<LlmResult> call(
    String systemPrompt,
    String userPrompt, {
    int? timeoutMs,
  }) async {
    callCount++;
    final e = throwError;
    if (e != null) throw e;
    return LlmResult(content: content, retryCount: 0);
  }
}

class FakeAlertSender implements DeveloperAlertSender {
  bool sendResult = true;
  int llmFatalCalls = 0;
  int structuralCalls = 0;
  int articleFailureCalls = 0;
  int batchReadyCalls = 0;
  final List<String> articleFailures = [];

  @override
  Future<bool> sendLlmFatalError(LlmFatal error, ErrorContext context) async {
    llmFatalCalls++;
    return sendResult;
  }

  @override
  Future<bool> sendStructuralError(Structural error, ErrorContext context) async {
    structuralCalls++;
    return sendResult;
  }

  @override
  Future<bool> sendArticleFailure({
    required String status,
    required String errorCode,
    required String errorMessage,
    required ErrorContext context,
  }) async {
    articleFailureCalls++;
    articleFailures.add('$status:$errorCode');
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
    batchReadyCalls++;
    return sendResult;
  }
}

Article _article(int id, ArticleStatus status, {int retryCount = 0}) => Article(
      id: id,
      batchId: 9,
      orderIndex: id,
      contentCategory: 'NEWS',
      title: null,
      status: status,
      generationStartedAt: null,
      generationCompletedAt: null,
      retryCount: retryCount,
      accumulatedReadSeconds: 0,
      readCompletedAt: null,
      lastRetryAt: null,
    );

void main() {
  late FakeArticleRepository repo;
  late FakeLlmClient llm;
  late FakeAlertSender alerts;
  late GenerateArticlesUseCase useCase;

  setUp(() {
    repo = FakeArticleRepository();
    llm = FakeLlmClient();
    alerts = FakeAlertSender();
    useCase = GenerateArticlesUseCase(
      articleRepository: repo,
      llmClient: llm,
      timeProvider: const FakeTimeProvider(),
      appInfo: const FakeAppInfoProvider(),
      alertSender: alerts,
    );
  });

  // ─── 成功路径 ────────────────────────────────────────────────────────

  test('全部文章成功后批次 READY 并通知飞书 通知送达后回写标记', () async {
    repo.articles = [
      _article(41, ArticleStatus.pending),
      _article(42, ArticleStatus.pending),
    ];
    repo.batchComplete = true;

    final result = await useCase(9, 1);

    expect(repo.markBatchReadyCalls, 1);
    expect(alerts.batchReadyCalls, 1);
    expect(repo.markBatchReadyNotifiedCalls, 1);
    expect(result, isTrue);
  });

  test('批次完成通知发送失败时不回写标记 留给启动补发', () async {
    repo.articles = [_article(41, ArticleStatus.pending)];
    repo.batchComplete = true;
    alerts.sendResult = false;

    final result = await useCase(9, 1);

    expect(repo.markBatchReadyNotifiedCalls, 0);
    expect(result, isTrue);
  });

  test('SUCCESS 文章跳过不重复生成', () async {
    repo.articles = [
      _article(41, ArticleStatus.success),
      _article(42, ArticleStatus.pending),
    ];
    repo.batchComplete = true;

    await useCase(9, 1);

    expect(llm.callCount, 1); // 只调用了一篇
    expect(repo.completedTitles.length, 1);
  });

  test('批次无文章时直接 READY', () async {
    repo.articles = [];

    final result = await useCase(9, 1);

    expect(repo.markBatchReadyCalls, 1);
    expect(alerts.batchReadyCalls, 0); // 空批次不发完成通知
    expect(result, isTrue);
  });

  // ─── 失败路径：错误日志 + 告警 + 送达标记 ───────────────────────────

  test('文章协程超时后按 LLM_TIMEOUT 分类写错误日志 告警送达则回写 notified_at',
      () async {
    repo.articles = [_article(42, ArticleStatus.pending)];
    llm.throwError = LlmTimeoutException('Timed out waiting for 300000 ms');

    await useCase(9, 1);

    expect(repo.failArticles, ['42:TIMEOUT:LLM_TIMEOUT']);
    expect(alerts.articleFailures, ['TIMEOUT:LLM_TIMEOUT']);
    expect(repo.notifiedIds, [100]);
  });

  test('超时告警发送失败时不回写 notified_at 下次启动补发', () async {
    repo.articles = [_article(42, ArticleStatus.pending)];
    llm.throwError = LlmTimeoutException('Timed out waiting for 300000 ms');
    alerts.sendResult = false;

    await useCase(9, 1);

    expect(repo.notifiedIds, isEmpty);
  });

  test('非超时的未知异常仍按 UNEXPECTED 分类', () async {
    repo.articles = [_article(42, ArticleStatus.pending)];
    llm.throwError = StateError('weird bug');

    await useCase(9, 1);

    expect(repo.failArticles, ['42:TIMEOUT:UNEXPECTED']);
    expect(alerts.articleFailures, ['TIMEOUT:UNEXPECTED']);
  });

  test('可恢复错误耗尽后文章 FAILED 并发送 FAILED 告警', () async {
    repo.articles = [_article(24, ArticleStatus.pending)];
    llm.throwError = LlmRecoverableExhaustedException(
        'LLM call failed after 3 retries',
        attempts: 3);

    await useCase(9, 1);

    expect(repo.failArticles, ['24:FAILED:LLM_RECOVERABLE_EXHAUSTED']);
    expect(alerts.articleFailures, ['FAILED:LLM_RECOVERABLE_EXHAUSTED']);
    expect(repo.notifiedIds, [100]);
  });

  test('致命错误发送 LLM Fatal 告警 批次保持 GENERATING 不 READY', () async {
    repo.articles = [_article(50, ArticleStatus.pending)];
    llm.throwError = LlmFatalException('auth failed');
    repo.hasFatal = true;

    final result = await useCase(9, 1);

    expect(repo.fatalArticles, ['50:LLM_FATAL']);
    expect(alerts.llmFatalCalls, 1);
    expect(repo.markErrorNotifiedCalls, 1);
    expect(repo.markBatchReadyCalls, 0);
    // FATAL 需人工介入：返回 true 表示批次已终结（不再重试），留待启动恢复
    expect(result, isTrue);
  });

  // ─── 未完成文章分支（回归：批次卡 GENERATING 修复） ─────────────────

  test('存在未完成文章时批次不 READY 且返回 false 触发 Worker 重试', () async {
    // 3 篇 SUCCESS + 2 篇冻结遗留 GENERATING（本轮无法认领）
    repo.articles = [
      _article(46, ArticleStatus.generating),
      _article(47, ArticleStatus.generating),
      _article(48, ArticleStatus.success),
      _article(49, ArticleStatus.success),
      _article(50, ArticleStatus.success),
    ];
    repo.claimResult = false;

    final result = await useCase(9, 1);

    expect(repo.markBatchReadyCalls, 0);
    expect(result, isFalse);
  });

  test('结构性错误阻塞管道 发送结构性告警并向上抛出', () async {
    repo.articles = [_article(50, ArticleStatus.pending)];
    llm.throwError = PipelineBlockingException('DB constraint violated');

    await expectLater(useCase(9, 1), throwsA(isA<PipelineBlockingException>()));

    expect(repo.fatalArticles, ['50:PIPELINE_BLOCKING']);
    expect(repo.batchBlockedReason, 'DB constraint violated');
    expect(alerts.structuralCalls, 1);
    // article + batch 两条流水账都回写
    expect(repo.markErrorNotifiedCalls, 2);
  });

  test('LLM 返回 XML 时解析标题与段落并写入 completeArticle', () async {
    llm.content = '<title>My Title</title>'
        '<paragraph>Hello world</paragraph><translation>你好世界</translation>'
        '<paragraph>Second line.</paragraph><translation>第二行。</translation>';
    repo.articles = [_article(41, ArticleStatus.pending)];
    repo.batchComplete = true;

    await useCase(9, 1);

    expect(repo.completedTitles, ['My Title']);
    expect(repo.completedParagraphs.single.length, 2);
    expect(repo.completedParagraphs.single[0].englishText, 'Hello world');
    expect(repo.completedParagraphs.single[1].chineseTranslation, '第二行。');
  });
}

class FakeTimeProvider implements TimeProvider {
  const FakeTimeProvider();

  @override
  int nowMillis() => 1785636000000;

  @override
  String nowDateTimeString() => '2026-07-31T10:30:00+08:00';

  @override
  String todayDateString() => '2026-07-31';
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
