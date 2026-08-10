/// LLM 客户端接口（对照 Kotlin LlmClient.kt），由 data 层实现。
abstract class LlmClient {
  /// 调用 LLM 生成内容。
  ///
  /// [timeoutMs] 为总预算超时（含重试等待），缺省 LLM_TIMEOUT_MS。
  ///
  /// 抛错语义：
  /// - [LlmFatalException] — LLM 服务级不可恢复错误
  /// - [LlmRecoverableExhaustedException] — 可恢复错误耗尽所有重试
  /// - [PipelineBlockingException] — 代码级结构性错误
  /// - [LlmTimeoutException] — 总预算超时
  Future<LlmResult> call(
    String systemPrompt,
    String userPrompt, {
    int? timeoutMs,
  });
}

/// LLM 调用结果：响应内容 + 实际重试次数。
class LlmResult {
  const LlmResult({required this.content, required this.retryCount});

  final String content;
  final int retryCount;
}
