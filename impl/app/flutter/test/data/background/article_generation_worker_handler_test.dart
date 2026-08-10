import 'package:contexta/data/background/article_generation_worker_handler.dart';
import 'package:contexta/domain/error/pipeline_blocking_exception.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/usecase/generate_articles_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// ArticleGenerationWorkerHandler 测试（对照 Kotlin ArticleGenerationWorker）：
/// - 无 batchId → 不重试（Kotlin Result.failure）
/// - claimBatch 失败（已抢占/已终结）→ true，不调用 use case
/// - finished=true → true；finished=false（仍有未完成文章）→ false 重试
/// - PipelineBlockingException → true 不重试（Kotlin Result.failure）
/// - 普通异常：attempt < 2 → false 重试；attempt >= 2 → true 放弃
/// - attempt 计数写入 inputData 并在每次运行后递增
void main() {
  late _FakeArticleRepository repo;
  late _FakeGenerateArticles useCase;
  late ArticleGenerationWorkerHandler handler;

  setUp(() {
    repo = _FakeArticleRepository();
    useCase = _FakeGenerateArticles();
    handler = ArticleGenerationWorkerHandler(
      articleRepository: repo,
      generateArticles: useCase,
    );
  });

  group('input 校验', () {
    test('无 inputData → 不重试（Kotlin Result.failure），不 claim', () async {
      final ok = await handler.run(null);
      expect(ok, isTrue);
      expect(repo.claimed, isEmpty);
      expect(useCase.calls, isEmpty);
    });

    test('batchId 缺失 → 不重试', () async {
      final ok = await handler.run({'appVersionCode': 1});
      expect(ok, isTrue);
      expect(repo.claimed, isEmpty);
    });

    test('batchId 非法类型/非正数 → 不重试', () async {
      expect(await handler.run({'batchId': 'abc'}), isTrue);
      expect(await handler.run({'batchId': 0}), isTrue);
      expect(await handler.run({'batchId': -3}), isTrue);
      expect(repo.claimed, isEmpty);
    });
  });

  group('批次 CAS 抢占', () {
    test('claimBatch 成功 → 调用 use case，appVersionCode 透传', () async {
      useCase.result = true;
      final ok = await handler.run(
          {'batchId': 6, 'appVersionCode': 12, 'attempt': 0});

      expect(ok, isTrue);
      expect(repo.claimed, [6]);
      expect(useCase.calls, [
        (batchId: 6, appVersionCode: 12),
      ]);
    });

    test('claimBatch 失败（已抢占/已终结）→ true 且不调用 use case', () async {
      repo.claimResult = false;
      final ok = await handler.run({'batchId': 6});

      expect(ok, isTrue);
      expect(useCase.calls, isEmpty);
    });
  });

  group('结果映射', () {
    test('finished=true → true（批次终结）', () async {
      useCase.result = true;
      expect(await handler.run({'batchId': 6}), isTrue);
    });

    test('finished=false（仍有 GENERATING/TIMEOUT/FAILED）→ false 重试', () async {
      useCase.result = false;
      expect(await handler.run({'batchId': 6}), isFalse);
    });

    test('PipelineBlockingException → true 不重试（Kotlin Result.failure）',
        () async {
      useCase.error = const PipelineBlockingException('constraint');
      expect(await handler.run({'batchId': 6}), isTrue);
    });
  });

  group('普通异常重试', () {
    test('attempt=0 抛出异常 → false（重试）', () async {
      useCase.error = Exception('boom');
      expect(await handler.run({'batchId': 6, 'attempt': 0}), isFalse);
    });

    test('attempt=1 抛出异常 → false（重试；Kotlin runAttemptCount<2）', () async {
      useCase.error = Exception('boom');
      expect(await handler.run({'batchId': 6, 'attempt': 1}), isFalse);
    });

    test('attempt=2 抛出异常 → true（放弃；Kotlin runAttemptCount>=2 failure）',
        () async {
      useCase.error = Exception('boom');
      expect(await handler.run({'batchId': 6, 'attempt': 2}), isTrue);
    });

    test('attempt 缺失时按 0 处理（首次运行可重试）', () async {
      useCase.error = Exception('boom');
      expect(await handler.run({'batchId': 6}), isFalse);
    });

    test('attempt 回写递增：每次运行后 inputData[attempt] 自增', () async {
      final input = {'batchId': 6, 'attempt': 1};
      useCase.error = Exception('boom');
      await handler.run(input);
      expect(input['attempt'], 2);
    });
  });
}

class _FakeArticleRepository implements ArticleRepository {
  bool claimResult = true;
  final List<int> claimed = [];

  @override
  Future<bool> claimBatch(int batchId) async {
    claimed.add(batchId);
    return claimResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGenerateArticles implements GenerateArticlesUseCase {
  bool result = true;
  Object? error;
  final List<({int batchId, int? appVersionCode})> calls = [];

  @override
  Future<bool> call(int batchId, int? appVersionCode) async {
    calls.add((batchId: batchId, appVersionCode: appVersionCode));
    final e = error;
    if (e != null) throw e;
    return result;
  }
}
