/// 代码级结构性错误（DB 约束冲突、序列化异常等），
/// 应触发 FATAL article 状态和 BLOCKED pipeline 状态。
///
/// message 原样透传调用方内容（LlmErrorClassifier 依赖其中的
/// "Constraint" / "disk I/O" 关键词做结构性错误分类）。
class PipelineBlockingException implements Exception {
  final String message;
  final Object? cause;

  const PipelineBlockingException(this.message, {this.cause});

  @override
  String toString() => 'PipelineBlockingException: $message';
}
