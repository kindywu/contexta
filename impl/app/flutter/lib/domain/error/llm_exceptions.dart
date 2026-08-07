/// LLM 相关异常（对齐 Kotlin LlmExceptions.kt）。
library;

/// Non-recoverable LLM-side error (auth, bad request, content policy)。
/// 对齐 Kotlin `LlmFatalException`。
class LlmFatalException implements Exception {
  final String message;
  final Object? cause;

  const LlmFatalException(this.message, {this.cause});

  @override
  String toString() => 'LlmFatalException: $message';
}

/// Recoverable error that exhausted all retries。
/// 对齐 Kotlin `LlmRecoverableExhaustedException`。
class LlmRecoverableExhaustedException implements Exception {
  final String message;
  final Object? cause;
  final int attempts;

  const LlmRecoverableExhaustedException(
    this.message, {
    this.cause,
    this.attempts = 0,
  });

  @override
  String toString() => 'LlmRecoverableExhaustedException: $message';
}

/// 协程级超时（withTimeoutOrNull 超时，LLM_TIMEOUT_MS）。
///
/// 与 [LlmRecoverableExhaustedException] 的区别：
/// - 后者是网络/服务层错误经过重试后耗尽（每次尝试有自己的超时）；
/// - 本异常是一次调用达到总预算超时，直接放弃。
/// 由 GenerateArticlesUseCase 分类为 TIMEOUT / LLM_TIMEOUT，而非 UNEXPECTED。
class LlmTimeoutException implements Exception {
  final String message;
  final Object? cause;

  const LlmTimeoutException(this.message, {this.cause});

  @override
  String toString() => 'LlmTimeoutException: $message';
}
