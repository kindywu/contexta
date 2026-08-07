import 'dart:io';

import '../../domain/error/pipeline_blocking_exception.dart';
import '../../domain/repository/article_repository.dart';
import '../../domain/usecase/generate_articles_usecase.dart';

/// 文章生成后台任务处理器（对照 Kotlin ArticleGenerationWorker.kt）。
///
/// 薄层：只做批次 CAS 抢占 + 调 Use Case + 结果映射，业务逻辑全部在
/// [GenerateArticlesUseCase]。
///
/// 结果语义（workmanager `executeTask` 返回 `Future<bool>`，false = retry）：
/// - 批次未抢占成功（已生成/已终结）→ true（非错误）
/// - finished → true；仍有未完成文章 → false（指数退避后重试）
/// - [PipelineBlockingException] → false 后不再重试（Kotlin Result.failure）
/// - 其他异常 → 重试最多 [maxAttempts] 次（Kotlin runAttemptCount < 2），
///   超过后放弃
///
/// workmanager 没有 runAttemptCount，attempt 计数由 inputData 携带并在每次
/// 运行后回写递增（对照 Kotlin runAttemptCount 语义：第 1 次 attempt=0 失败
/// 可重试 → attempt=1 失败仍可重试 → attempt=2 失败放弃）。
class ArticleGenerationWorkerHandler {
  ArticleGenerationWorkerHandler({
    required this.articleRepository,
    required this.generateArticles,
    this.maxAttempts = 2,
  });

  static const String keyBatchId = 'batchId';
  static const String keyAppVersionCode = 'appVersionCode';
  static const String keyAttempt = 'attempt';

  final ArticleRepository articleRepository;
  final GenerateArticlesUseCase generateArticles;
  final int maxAttempts;

  /// 执行批次生成。返回 true = 任务成功终结（或无需处理），
  /// false = 应重试（Kotlin Result.retry()）。
  Future<bool> run(Map<String, dynamic>? inputData) async {
    final batchId = inputData?[keyBatchId];
    if (batchId is! int || batchId <= 0) {
      stderr.writeln('ArticleGenerationWorker: missing/invalid batchId '
          'in input data: $inputData');
      // Kotlin: 无 batchId → Result.failure()（不重试）
      return true;
    }

    final appVersionCode = inputData?[keyAppVersionCode];
    final attempt = inputData?[keyAttempt];
    final currentAttempt =
        attempt is int && attempt > 0 ? attempt : 0;
    inputData?[keyAttempt] = currentAttempt + 1;

    stderr.writeln('ArticleGenerationWorker: doWork: '
        'batchId=$batchId, attempt=$currentAttempt');

    // CAS 抢占批次（对照 Kotlin claimBatch → 失败即 success 返回）
    if (!await articleRepository.claimBatch(batchId)) {
      stderr.writeln('ArticleGenerationWorker: batch $batchId claim '
          'failed (already claimed or terminal)');
      return true;
    }
    stderr.writeln('ArticleGenerationWorker: batch $batchId claimed');

    try {
      final finished = await generateArticles(batchId, appVersionCode);
      stderr.writeln('ArticleGenerationWorker: batch $batchId finished='
          '$finished');
      // 仍有未完成文章（GENERATING/TIMEOUT/FAILED）→ 重试
      return finished;
    } on PipelineBlockingException catch (e) {
      stderr.writeln('ArticleGenerationWorker: structural error for batch '
          '$batchId: ${e.message}');
      // Kotlin: PipelineBlockingException → Result.failure()，不重试
      return true;
    } catch (e) {
      stderr.writeln('ArticleGenerationWorker: unexpected error for batch '
          '$batchId: $e');
      // Kotlin: runAttemptCount < 2 → retry（返回 false），否则 failure
      return currentAttempt >= maxAttempts;
    }
  }
}
