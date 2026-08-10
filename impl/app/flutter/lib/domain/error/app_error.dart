/// 统一错误类型（对齐 Kotlin AppError.kt），分为三类：
/// - [Recoverable]：可自动重试（网络超时、限流、服务端错误等）
/// - [LlmFatal]：LLM 服务级不可恢复（认证失败、内容策略拒绝等），需开发者介入
/// - [Structural]：代码级 bug（DB 约束冲突、序列化异常等），阻塞 pipeline
///
/// 注意：Kotlin 中三个子类嵌套在 AppError 内（`AppError.Recoverable`），
/// Dart 不支持嵌套类声明，故平铺为顶层类（sealed 层级结构保持不变）。
sealed class AppError {
  const AppError();
}

/// 可恢复错误 — 自动重试，耗尽后用户可手动重试。
class Recoverable extends AppError {
  final RecoverableCode code;
  final String message;
  final Object? cause;
  final int? retryAfterSeconds;

  const Recoverable({
    required this.code,
    required this.message,
    this.cause,
    this.retryAfterSeconds,
  });
}

/// LLM 不可恢复 — 服务级错误（换 API Key、改设置等），需开发者介入。
class LlmFatal extends AppError {
  final LlmFatalCode code;
  final String message;
  final Object? cause;

  const LlmFatal({
    required this.code,
    required this.message,
    this.cause,
  });
}

/// 结构性错误 — 代码 bug，需开发者介入。
class Structural extends AppError {
  final StructuralCode code;
  final String message;
  final Object? cause;

  const Structural({
    required this.code,
    required this.message,
    this.cause,
  });
}

/// 可恢复错误码（对齐 Kotlin RecoverableCode）。
enum RecoverableCode {
  networkTimeout('NETWORK_TIMEOUT'),
  rateLimited('RATE_LIMITED'),
  serverError('SERVER_ERROR'),
  jsonParseFailed('JSON_PARSE_FAILED'),
  llmTimeout('LLM_TIMEOUT');

  const RecoverableCode(this.dbValue);

  /// DB 存储值（对齐 Kotlin `Enum.name`，Feishu 告警 errorCode 用）。
  final String dbValue;

  String toDbValue() => dbValue;

  static RecoverableCode fromDbValue(String value) {
    for (final c in values) {
      if (c.dbValue == value) return c;
    }
    throw ArgumentError('Unknown RecoverableCode: $value');
  }

  @override
  String toString() => dbValue;
}

/// LLM 不可恢复错误码（对齐 Kotlin LlmFatalCode）。
enum LlmFatalCode {
  authFailed('AUTH_FAILED'), // 401/403
  badRequest('BAD_REQUEST'), // 400
  contentPolicy('CONTENT_POLICY'), // 内容被拒绝
  emptyResponse('EMPTY_RESPONSE'); // LLM 返回空内容

  const LlmFatalCode(this.dbValue);

  /// DB 存储值（对齐 Kotlin `Enum.name`，Feishu 告警 errorCode 用）。
  final String dbValue;

  String toDbValue() => dbValue;

  static LlmFatalCode fromDbValue(String value) {
    for (final c in values) {
      if (c.dbValue == value) return c;
    }
    throw ArgumentError('Unknown LlmFatalCode: $value');
  }

  @override
  String toString() => dbValue;
}

/// 结构性错误码（对齐 Kotlin StructuralCode）。
enum StructuralCode {
  dbConstraintViolation('DB_CONSTRAINT_VIOLATION'),
  serializationError('SERIALIZATION_ERROR'),
  diskIoError('DISK_IO_ERROR'),
  illegalState('ILLEGAL_STATE'),
  unexpectedError('UNEXPECTED_ERROR');

  const StructuralCode(this.dbValue);

  /// DB 存储值（对齐 Kotlin `Enum.name`，Feishu 告警 errorCode 用）。
  final String dbValue;

  String toDbValue() => dbValue;

  static StructuralCode fromDbValue(String value) {
    for (final c in values) {
      if (c.dbValue == value) return c;
    }
    throw ArgumentError('Unknown StructuralCode: $value');
  }

  @override
  String toString() => dbValue;
}
