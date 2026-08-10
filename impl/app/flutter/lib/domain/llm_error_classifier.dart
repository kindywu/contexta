import 'error/pipeline_blocking_exception.dart';

/// LLM 调用错误三分类（对照 Kotlin LlmErrorClassifier.kt 的 sealed class）。
///
/// - [RecoverableError] — 网络问题、429 限流、5xx、坏 JSON → 可重试
/// - [FatalError] — 401/403 鉴权、400 坏请求、内容策略 → 立即失败，用户可重试
/// - [StructuralError] — DB 约束冲突、序列化错误 → BLOCKED 状态
sealed class LlmError {
  const LlmError(this.cause);

  /// 原始异常（Kotlin: cause）。
  final Object cause;
}

/// 可恢复 — 退避重试。
class RecoverableError extends LlmError {
  const RecoverableError(super.cause, {this.retryAfterSeconds});

  /// 429 时服务端建议的等待秒数（Retry-After 头）。
  final int? retryAfterSeconds;
}

/// LLM 侧不可恢复错误 — 立即失败任务，用户可重试。
class FatalError extends LlmError {
  const FatalError(super.cause);
}

/// 代码级结构性错误 — 阻塞流水线，需应用修复。
class StructuralError extends LlmError {
  const StructuralError(super.cause);
}

/// 分类器（纯函数，对照 Kotlin object LlmErrorClassifier）。
class LlmErrorClassifier {
  LlmErrorClassifier._();

  static LlmError classify(int? httpCode, Object error) {
    // 结构性错误优先——它们是本地错误，不是 LLM 响应
    final message = error is Exception ? error.toString() : error.toString();
    if (error is PipelineBlockingException) {
      return StructuralError(error);
    }
    if (message.contains('Constraint')) {
      return StructuralError(error);
    }
    if (message.contains('disk I/O')) {
      return StructuralError(error);
    }

    final code = httpCode;
    if (code == null) {
      // 网络错误（未解析出 HTTP 状态码）→ 可恢复
      return RecoverableError(error);
    }
    if (code == 429) {
      return RecoverableError(error, retryAfterSeconds: _extractRetryAfter(message));
    }
    if (code >= 500 && code <= 599) {
      return RecoverableError(error);
    }
    if (message.contains('JSON') ||
        message.contains('parse') ||
        message.contains('syntax')) {
      return RecoverableError(error);
    }

    // LLM 致命错误
    if (code == 400 || code == 401 || code == 403) {
      return FatalError(error);
    }

    // 其他 → 保守可恢复
    return RecoverableError(error);
  }

  /// 从异常消息提取 Retry-After 秒数（Kotlin 正则 `Retry-After[=:\s]+(\d+)`）。
  static int? _extractRetryAfter(String message) {
    final match = RegExp(r'Retry-After[=:\s]+(\d+)').firstMatch(message);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
