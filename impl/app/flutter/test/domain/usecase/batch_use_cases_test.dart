import 'package:contexta/domain/model/article_batch.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:contexta/domain/usecase/activate_seed_batch_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// ActivateSeedBatchUseCase 测试（2026-08-13 计划 B Task 6：TriggerNextBatch /
/// CreateInitialBatch 已随本地生成管道删除，仅保留种子激活语义）。

class FakeArticleRepository implements ArticleRepository {
  ArticleBatch? nextReady;
  final List<String> assignCalls = [];

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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

  setUp(() {
    repo = FakeArticleRepository();
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
