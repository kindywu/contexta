import '../../core/time/iso8601.dart';
import '../app_info_provider.dart';
import '../developer_alert_sender.dart';
import '../error/app_error.dart';
import '../repository/article_repository.dart';
import '../time/time_provider.dart';

/// 补发未送达的飞书告警（对照 Kotlin ResendPendingAlertsUseCase.kt）。
///
/// 实时告警是尽力而为：生成期间进程可能被系统终止（后台冻结/Job 超时），
/// sendArticleFailure / sendBatchReady 的 HTTP 调用可能未完成就随进程消失。
/// 错误事件已落库（generation_error_log），批次状态已落库（article_batch），
/// 但通知标记（notified_at / ready_notified_at）仍为 null —— 启动时补发这些告警。
///
/// 幂等保证：
/// - 告警发送成功才回写 notified_at（SQL 带 `AND notified_at IS NULL` 条件，只写一次）
/// - 发送失败（返回 false）不回写，下次启动继续补发
class ResendPendingAlertsUseCase {
  ResendPendingAlertsUseCase({
    required this._articleRepository,
    required this._alertSender,
    required this._timeProvider,
    required this._appInfo,
  });

  final ArticleRepository _articleRepository;
  final DeveloperAlertSender _alertSender;
  final TimeProvider _timeProvider;
  final AppInfoProvider _appInfo;

  /// 只补发最近 24 小时内的错误，更早的视为已处理完毕（人工可见于错误历史）。
  static const int _lookbackMs = 24 * 60 * 60 * 1000;

  Future<void> call() async {
    final now = _timeProvider.nowMillis();
    final sinceIso =
        isoOffsetDateTime(DateTime.fromMillisecondsSinceEpoch(now - _lookbackMs));

    // 1. 补发未通知的错误告警
    final unnotifiedErrors = await _articleRepository.getUnnotifiedErrors(sinceIso);
    for (final error in unnotifiedErrors) {
      final batchId = error.entityType == 'BATCH'
          ? error.entityId
          : (await _articleRepository.getArticle(error.entityId))?.batchId;
      final context = ErrorContext(
        batchId: batchId,
        articleId: error.entityType == 'ARTICLE' ? error.entityId : null,
        appVersion: _appInfo.versionCode,
        timestamp: now,
      );
      final sent = switch (error.errorCode) {
        'LLM_FATAL' => await _alertSender.sendLlmFatalError(
            LlmFatal(
              code: LlmFatalCode.authFailed,
              message: error.errorMessage,
            ),
            context,
          ),
        'STRUCTURAL_PIPELINE_BLOCKED' || 'PIPELINE_BLOCKING' =>
          await _alertSender.sendStructuralError(
            Structural(
              code: StructuralCode.unexpectedError,
              message: error.errorMessage,
            ),
            context,
          ),
        _ => await _alertSender.sendArticleFailure(
            status:
                error.errorCode == 'LLM_RECOVERABLE_EXHAUSTED' ? 'FAILED' : 'TIMEOUT',
            errorCode: error.errorCode,
            errorMessage: error.errorMessage,
            context: context,
          ),
      };
      if (sent) {
        await _articleRepository.markErrorNotified(error.id);
      }
    }

    // 2. 补发未通知的批次完成告警
    final unnotifiedBatches = await _articleRepository.getReadyBatchesUnnotified();
    for (final batch in unnotifiedBatches) {
      final articleCount = (await _articleRepository.getArticles(batch.id)).length;
      final sent = await _alertSender.sendBatchReady(
        batchId: batch.id,
        articleCount: articleCount,
        batchGeneratedOn: batch.generatedOn,
        batchDifficulty: batch.difficultyLevelSnapshot,
        context: ErrorContext(
          batchId: batch.id,
          articleId: null,
          appVersion: _appInfo.versionCode,
          timestamp: now,
        ),
      );
      if (sent) {
        await _articleRepository.markBatchReadyNotified(batch.id);
      }
    }
  }
}
