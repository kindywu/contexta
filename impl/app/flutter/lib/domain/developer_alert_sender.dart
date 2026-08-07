import 'error/app_error.dart';

/// 错误上下文，由 Use Case 层在捕获异常时构造（对照 Kotlin ErrorContext）。
/// 所有字段由调用方显式传入，保持 domain 纯净。
class ErrorContext {
  const ErrorContext({
    this.batchId,
    this.articleId,
    this.appVersion = 0,
    required this.timestamp,
  });

  final int? batchId;
  final int? articleId;
  final int appVersion;

  /// 调用方通过 TimeProvider.nowMillis() 传入。
  final int timestamp;
}

/// 开发者通知接口（对照 Kotlin DeveloperAlertSender.kt）。
/// 用于不可恢复或需要关注的错误，通知失败不应影响主流程。
abstract interface class DeveloperAlertSender {
  /// 发送 LLM 不可恢复错误通知（API Key 失效、账号欠费等）。
  /// 返回 true = 通知已发出（或被去重视为已处理）；false = 发送失败，
  /// 调用方可回写/保留待补发标记。
  Future<bool> sendLlmFatalError(LlmFatal error, ErrorContext context);

  /// 发送结构性错误通知（代码级 bug）。
  Future<bool> sendStructuralError(Structural error, ErrorContext context);

  /// 发送文章生成失败通知（TIMEOUT / FAILED / FATAL 等非 SUCCESS 终态）。
  Future<bool> sendArticleFailure({
    required String status,
    required String errorCode,
    required String errorMessage,
    required ErrorContext context,
  });

  /// 发送批次生成完成通知（心跳/状态确认）。
  /// [batchGeneratedOn] / [batchDifficulty] 可为 null，通知中显示 ?。
  Future<bool> sendBatchReady({
    required int batchId,
    required int articleCount,
    required String? batchGeneratedOn,
    required String? batchDifficulty,
    required ErrorContext context,
  });
}
