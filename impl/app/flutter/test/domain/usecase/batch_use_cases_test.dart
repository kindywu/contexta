import 'package:contexta/domain/background_work_scheduler.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/model/daily_learning_info.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/activate_seed_batch_usecase.dart';
import 'package:contexta/domain/usecase/create_initial_batch_usecase.dart';
import 'package:contexta/domain/usecase/trigger_next_batch_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// TriggerNextBatch / ActivateSeedBatch / CreateInitialBatch 的联合测试
/// （Kotlin 端无对应测试文件，按实现语义新写）。

class FakeArticleRepository implements ArticleRepository {
  List<ArticleBatch> unassigned = [];
  ArticleBatch? existingToday;
  ArticleBatch? unassignedToday;
  ArticleBatch? nextReady;
  int nextBatchId = 100;
  final List<String> createCalls = [];
  final List<String> createArticlesCalls = [];
  final List<String> assignCalls = [];

  @override
  Future<List<ArticleBatch>> getUnassignedReadyBatches(
      String difficulty, String? minGeneratedOn) async {
    return unassigned;
  }

  @override
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
      String difficulty, String date) async {
    return existingToday;
  }

  @override
  Future<ArticleBatch?> getUnassignedBatchByDifficultyAndDate(
      String difficulty, String date) async {
    return unassignedToday;
  }

  
  @override
  Future<List<ArticleBatch>> getPendingBatches() => throw UnimplementedError();

@override
  Future<int> createBatch(String difficulty, {String? generatedOn}) async {
    createCalls.add('$difficulty:$generatedOn');
    return nextBatchId;
  }

  @override
  Future<void> createArticles(int batchId, List<String> categories) async {
    createArticlesCalls.add('$batchId:${categories.join(',')}');
  }

  @override
  Future<ArticleBatch?> findNextReadyBatch(
      String difficulty, String? afterDate) async {
    return nextReady;
  }

  @override
  Future<bool> assignBatchForToday(
      int batchId, String refBatchDate, int dailyCount) async {
    assignCalls.add('$batchId:$refBatchDate:$dailyCount');
    return true;
  }

  @override
  Future<String?> getMaxRefBatchDate() async => null;

  @override
  Stream<List<Article>> observeArticles(int batchId) =>
      throw UnimplementedError();

  @override
  Future<Article?> getArticle(int articleId) => throw UnimplementedError();

  @override
  Future<bool> isPipelineBlocked() => throw UnimplementedError();

  @override
  Future<bool> recoverIfNewerVersion(int currentVersionCode) =>
      throw UnimplementedError();

  @override
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate) =>
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
  Future<List<Article>> getArticles(int batchId) => throw UnimplementedError();

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

class FakeScheduler implements BackgroundWorkScheduler {
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

ArticleBatch _readyBatch(int id, {String difficulty = 'LOW'}) => ArticleBatch(
      id: id,
      status: BatchStatus.ready,
      difficultyLevelSnapshot: difficulty,
      generatedOn: '2026-07-31',
      lastUpdatedAt: '2026-07-31T21:25:42+08:00',
    );

void main() {
  late FakeArticleRepository repo;
  late FakeScheduler scheduler;

  setUp(() {
    repo = FakeArticleRepository();
    scheduler = FakeScheduler();
  });

  group('TriggerNextBatchUseCase', () {
    late TriggerNextBatchUseCase useCase;

    setUp(() {
      useCase = TriggerNextBatchUseCase(
        articleRepository: repo,
        generationScheduler: scheduler,
        timeProvider: const FakeTimeProvider(),
      );
    });

    test('已有比已分配批次更新的 READY 批次时跳过创建', () async {
      repo.unassigned = [_readyBatch(6)];

      await useCase('LOW', 3);

      expect(repo.createCalls, isEmpty);
      expect(scheduler.scheduled, isEmpty);
    });

    test('今天已有未消费的同难度批次时跳过（防重入）', () async {
      repo.unassignedToday = _readyBatch(5);

      await useCase('LOW', 3);

      expect(repo.createCalls, isEmpty);
      expect(scheduler.scheduled, isEmpty);
    });

    test('无可用批次时创建新批次并调度 Worker', () async {
      await useCase('LOW', 3);

      expect(repo.createCalls, ['LOW:2026-08-02']);
      expect(repo.createArticlesCalls, hasLength(1));
      expect(scheduler.scheduled, [100]);
    });

    test('今天创建且已消费的批次不挡预生成（防重入修复）', () async {
      // 2026-08-12：当天创建当天消费后，未消费查询返回 null →
      // 允许再次创建（预生成下一次），断签后链条可自愈。
      repo.existingToday = _readyBatch(5); // 旧的"今天已有"查询不再生效
      repo.unassignedToday = null; // 今天已无未消费批次

      await useCase('LOW', 3);

      expect(repo.createCalls, ['LOW:2026-08-02']);
      expect(scheduler.scheduled, [100]);
    });

    test('固定生成 5 篇文章（生成数量与显示数量分离）', () async {
      await useCase('MEDIUM', 1);

      final parts = repo.createArticlesCalls.single.split(':');
      expect(parts.last.split(',').length, 5);
    });

    test('未知难度回退 MEDIUM 分类组', () {
      final categories = useCase.pickCategories('UNKNOWN');
      expect(categories.length, 5);
      for (final c in categories) {
        expect(TriggerNextBatchUseCase.contentCategories['MEDIUM'], contains(c));
      }
    });

    test('pickCategories 基于 nowMillis 偏移 round-robin', () {
      // FakeTimeProvider.nowMillis() = 1785636000000 → 1785636000000 % 1000 = 0
      final categories = useCase.pickCategories('LOW');
      expect(categories.length, 5);
      final available = TriggerNextBatchUseCase.contentCategories['LOW']!;
      for (var i = 0; i < 5; i++) {
        expect(categories[i], available[i % available.length]);
      }
    });
  });

  group('ActivateSeedBatchUseCase', () {
    late ActivateSeedBatchUseCase useCase;

    setUp(() {
      useCase = ActivateSeedBatchUseCase(
        articleRepository: repo,
        timeProvider: const FakeTimeProvider(),
      );
    });

    test('找到种子批次时分配给今天并返回 true', () async {
      repo.nextReady = _readyBatch(6);

      final result = await useCase('LOW', 3);

      expect(result, isTrue);
      expect(repo.assignCalls, ['6:2026-07-31:3']);
    });

    test('批次 generatedOn 为 null 时用今天日期', () async {
      repo.nextReady = ArticleBatch(
        id: 6,
        status: BatchStatus.ready,
        difficultyLevelSnapshot: 'LOW',
        generatedOn: null,
        lastUpdatedAt: '2026-07-31T21:25:42+08:00',
      );

      await useCase('LOW', 3);

      expect(repo.assignCalls, ['6:2026-08-01:3']);
    });

    test('无匹配种子时返回 false', () async {
      repo.nextReady = null;

      final result = await useCase('HIGH', 3);

      expect(result, isFalse);
      expect(repo.assignCalls, isEmpty);
    });
  });

  group('CreateInitialBatchUseCase', () {
    late CreateInitialBatchUseCase useCase;

    setUp(() {
      useCase = CreateInitialBatchUseCase(
        articleRepository: repo,
        triggerNextBatch: TriggerNextBatchUseCase(
          articleRepository: repo,
          generationScheduler: scheduler,
          timeProvider: const FakeTimeProvider(),
        ),
        timeProvider: const FakeTimeProvider(),
      );
    });

    test('创建批次 建文章 并立即分配到今天', () async {
      final batchId = await useCase('LOW', 5);

      expect(batchId, 100);
      expect(repo.createCalls, ['LOW:null']);
      expect(repo.createArticlesCalls, hasLength(1));
      expect(repo.assignCalls, ['100:2026-08-01:5']);
    });
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
