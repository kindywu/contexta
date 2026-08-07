import '../app_info_provider.dart';
import '../developer_alert_sender.dart';
import '../error/app_error.dart';
import '../error/llm_exceptions.dart';
import '../error/pipeline_blocking_exception.dart';
import '../generation/article_prompts.dart';
import '../llm_client.dart';
import '../model/article.dart';
import '../repository/article_repository.dart';
import '../time/time_provider.dart';

/// 通过 LLM 生成一个批次的所有文章（对照 Kotlin GenerateArticlesUseCase.kt）。
///
/// 从 Android 的 ArticleGenerationWorker.processBatch 提取：
/// - 逐篇 CAS 认领（失败跳过）
/// - 按异常分类处理：TIMEOUT → TIMEOUT/LLM_TIMEOUT；RecoverableExhausted →
///   FAILED；LlmFatal → FATAL/LLM_FATAL；PipelineBlocking → FATAL +
///   BATCH BLOCKED + 全局阻塞开关并向上抛出
/// - 批次终结判定：FATAL → true（留 GENERATING 等待启动恢复）；
///   全部 SUCCESS → READY + 飞书完成通知；仍有未完成 → false（Worker 重试）
class GenerateArticlesUseCase {
  // appInfo 与 Kotlin 构造签名对齐保留；版本信息由调用方以 appVersionCode 传入
  GenerateArticlesUseCase({
    required this._articleRepository,
    required this._llmClient,
    required this._timeProvider,
    required AppInfoProvider appInfo,
    required this._alertSender,
  });

  final ArticleRepository _articleRepository;
  final LlmClient _llmClient;
  final TimeProvider _timeProvider;
  final DeveloperAlertSender _alertSender;

  /// 为指定的批次生成所有文章。
  ///
  /// 返回 true 表示批次已终结（READY 或留 GENERATING 等待启动恢复），
  /// false 表示仍存在未完成文章（GENERATING/TIMEOUT/FAILED），
  /// 调用方应重试。
  Future<bool> call(int batchId, int? appVersionCode) async {
    final articles = await _articleRepository.getArticles(batchId);
    if (articles.isEmpty) {
      await _articleRepository.markBatchReady(batchId);
      return true;
    }

    for (final article in articles) {
      if (article.status == ArticleStatus.success) continue;

      if (!await _articleRepository.claimArticle(article.id)) continue;

      try {
        final difficulty = categoryToDifficulty(article.contentCategory);
        final result = await _llmClient.call(
          await buildArticleSystemPrompt(difficulty),
          await buildArticleUserPrompt(article.contentCategory, article.orderIndex),
        );

        final parsed = parseArticleLlmResponse(result.content);
        await _articleRepository.completeArticle(
          article.id,
          parsed.title,
          parsed.paragraphs,
          retryCount: result.retryCount,
        );
      } on LlmFatalException catch (e) {
        final errorLogId = await _articleRepository.fatalArticle(
          article.id,
          errorCode: 'LLM_FATAL',
          errorMessage: e.message,
          retryCount: article.retryCount,
        );
        // 告警送达才回写 notified_at；进程被杀导致通知丢失时，启动补发会重发
        final sent = await _alertSender.sendLlmFatalError(
          LlmFatal(
            code: LlmFatalCode.authFailed,
            message: e.message,
            cause: e,
          ),
          _context(batchId, article.id, appVersionCode),
        );
        if (sent && errorLogId != null) {
          await _articleRepository.markErrorNotified(errorLogId);
        }
      } on LlmRecoverableExhaustedException catch (e) {
        final errorLogId = await _articleRepository.failArticle(
          article.id,
          'FAILED',
          errorCode: 'LLM_RECOVERABLE_EXHAUSTED',
          errorMessage: e.message,
          retryCount: article.retryCount,
        );
        final sent = await _alertSender.sendArticleFailure(
          status: 'FAILED',
          errorCode: 'LLM_RECOVERABLE_EXHAUSTED',
          errorMessage: e.message,
          context: _context(batchId, article.id, appVersionCode),
        );
        if (sent && errorLogId != null) {
          await _articleRepository.markErrorNotified(errorLogId);
        }
      } on PipelineBlockingException catch (e) {
        final articleErrorLogId = await _articleRepository.fatalArticle(
          article.id,
          errorCode: 'PIPELINE_BLOCKING',
          errorMessage: e.message,
          retryCount: article.retryCount,
        );
        final batchErrorLogId = await _articleRepository.markBatchBlocked(
          batchId,
          e.message,
          appVersionCode ?? 0,
        );
        final sent = await _alertSender.sendStructuralError(
          Structural(
            code: StructuralCode.unexpectedError,
            message: e.message,
            cause: e,
          ),
          _context(batchId, article.id, appVersionCode),
        );
        if (sent) {
          if (articleErrorLogId != null) {
            await _articleRepository.markErrorNotified(articleErrorLogId);
          }
          if (batchErrorLogId != null) {
            await _articleRepository.markErrorNotified(batchErrorLogId);
          }
        }
        rethrow;
      } on LlmTimeoutException catch (e) {
        // 协程级超时：预期内的失败（网络挂起/后台节流），
        // 单独分类为 LLM_TIMEOUT，区别于真正的 UNEXPECTED 代码级错误
        final errorLogId = await _articleRepository.failArticle(
          article.id,
          'TIMEOUT',
          errorCode: 'LLM_TIMEOUT',
          errorMessage: e.message,
          retryCount: article.retryCount,
        );
        final sent = await _alertSender.sendArticleFailure(
          status: 'TIMEOUT',
          errorCode: 'LLM_TIMEOUT',
          errorMessage: e.message,
          context: _context(batchId, article.id, appVersionCode),
        );
        if (sent && errorLogId != null) {
          await _articleRepository.markErrorNotified(errorLogId);
        }
      } catch (e) {
        final errorLogId = await _articleRepository.failArticle(
          article.id,
          'TIMEOUT',
          errorCode: 'UNEXPECTED',
          errorMessage: e.toString(),
          retryCount: article.retryCount,
        );
        final sent = await _alertSender.sendArticleFailure(
          status: 'TIMEOUT',
          errorCode: 'UNEXPECTED',
          errorMessage: e.toString(),
          context: _context(batchId, article.id, appVersionCode),
        );
        if (sent && errorLogId != null) {
          await _articleRepository.markErrorNotified(errorLogId);
        }
      }
    }

    if (await _articleRepository.hasFatalArticle(batchId)) {
      // FATAL 需要人工介入：留 GENERATING，启动恢复时重置重试
      return true;
    }
    if (await _articleRepository.isBatchComplete(batchId)) {
      await _articleRepository.markBatchReady(batchId);
      // 取批次信息（生成日期/难度），随完成通知一起展示
      final batch = await _articleRepository.getBatchById(batchId);
      final sent = await _alertSender.sendBatchReady(
        batchId: batchId,
        articleCount: articles.length,
        batchGeneratedOn: batch?.generatedOn,
        batchDifficulty: batch?.difficultyLevelSnapshot,
        context: _context(batchId, null, appVersionCode),
      );
      // 通知送达才回写 ready_notified_at；进程被杀导致通知丢失时，启动补发会重发
      if (sent) {
        await _articleRepository.markBatchReadyNotified(batchId);
      }
      return true;
    }

    // 仍存在未完成文章（GENERATING/TIMEOUT/FAILED）：
    // 不标记 READY，返回 false 让 Worker 重试（runAttempt 上限内）。
    return false;
  }

  ErrorContext _context(int batchId, int? articleId, int? appVersionCode) =>
      ErrorContext(
        batchId: batchId,
        articleId: articleId,
        appVersion: appVersionCode ?? 0,
        timestamp: _timeProvider.nowMillis(),
      );
}
