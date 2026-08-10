/// 文章生成错误事件（来自 generation_error_log 流水账，对齐 Kotlin
/// GenerationError.kt）。
///
/// [status] 是实体表的状态投影（如 'FAILED' / 'TIMEOUT' / 'FATAL'），
/// 用于 UI 判断是否可以重试；实体已删除时为 null。
class GenerationError {
  /// generation_error_log 主键（补发告警后回写 notified_at 用）
  final int id;

  final int entityId;
  final String entityType; // 'ARTICLE' | 'BATCH'
  final String errorCode;
  final String errorMessage;
  final String? errorHelp;
  final int retryCount;
  final String createdAt;
  final String? status;

  const GenerationError({
    required this.id,
    required this.entityId,
    this.entityType = 'ARTICLE',
    required this.errorCode,
    required this.errorMessage,
    required this.errorHelp,
    required this.retryCount,
    required this.createdAt,
    this.status,
  });

  @override
  String toString() => 'GenerationError(id=$id, entityId=$entityId, '
      'entityType=$entityType, errorCode=$errorCode, '
      'errorMessage=$errorMessage, errorHelp=$errorHelp, '
      'retryCount=$retryCount, createdAt=$createdAt, status=$status)';
}
