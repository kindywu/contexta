/// 代码级结构性错误（DB 约束冲突、序列化异常等），
/// 应触发 FATAL article 状态和 BLOCKED pipeline 状态。
///
/// message 原样透传调用方内容（查词/加词调用点经
/// mapErrorCodeToException 映射后展示，见 server_api_client.dart）。
class PipelineBlockingException implements Exception {
  final String message;
  final Object? cause;

  const PipelineBlockingException(this.message, {this.cause});

  @override
  String toString() => 'PipelineBlockingException: $message';
}
