import 'package:dio/dio.dart';

import '../../domain/error/llm_exceptions.dart';
import '../../domain/error/pipeline_blocking_exception.dart';

/// 服务端协议错误（envelope 非零 code，或非 2xx 错误响应）。
///
/// - [errorCode]：服务端 error_code 枚举（TOKEN_EXPIRED / EVICTED / BANNED /
///   QUOTA_EXCEEDED / LLM_* / PIPELINE_BLOCKING / BAD_PARAM ...）；
///   网络层错误固定为 'NETWORK'，无法解析时兜底 'UNKNOWN'。
/// - [statusCode]：HTTP 状态码；网络错误时为 null。
class ServerApiException implements Exception {
  final String errorCode;
  final String message;
  final int? statusCode;

  const ServerApiException({
    required this.errorCode,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ServerApiException: [$errorCode] $message';
}

/// 认证失败类别：401 TOKEN_EXPIRED / EVICTED，403 BANNED。
///
/// 定义在本文件（而非 auth_service）避免 data/remote 与 data/auth 循环依赖：
/// auth_service import 本枚举，ServerApiClient 不依赖 auth_service。
enum AuthFailureKind { tokenExpired, evicted, banned }

/// 服务端统一 API 客户端：envelope 解包 + 认证拦截 + error_code → [ServerApiException]。
///
/// 契约（服务端约定，字段名精确）：
/// - 成功：HTTP 2xx + `{code: 0, data}` → 返回 data（可选 [parser] 转换）；
/// - 业务错误：2xx + `code != 0` → 解包 `{message, error_code}` 抛 [ServerApiException]；
/// - 协议错误：非 2xx + `{code, message, error_code}` → 同上；
/// - 认证失败：TOKEN_EXPIRED / EVICTED / BANNED 额外触发 [setAuthCallback] 回调
///   （上层据此登出 / 提示），不吞掉异常；
/// - 网络错误（连接失败 / 连接超时）→ errorCode 'NETWORK'（调用点经
///   [mapErrorCodeToException] 按 LlmTimeoutException 处理，与服务端超时同语义）。
///
/// [baseUrl] 为服务端 origin（无尾斜杠，见 AppConfig.serverBaseUrl），[path] 以
/// `/` 开头；拼接方式 `'$baseUrl$path'`。Bearer 头经拦截器注入：每次请求从
/// [tokenProvider] 取最新 token，返回 null 时不附加。
class ServerApiClient {
  ServerApiClient(this._dio, {required this.baseUrl, required this.tokenProvider}) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenProvider();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;
  final String baseUrl;

  /// 当前登录 token（null = 未登录，不附加 Authorization 头）。
  final Future<String?> Function() tokenProvider;

  void Function(AuthFailureKind kind)? _authCallback;

  /// 注册认证失败回调（登录失效 / 踢下线 / 封禁 → 由上层决定登出提示等）。
  void setAuthCallback(void Function(AuthFailureKind kind)? cb) => _authCallback = cb;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    T Function(dynamic)? parser,
  }) =>
      _request<T>(() => _dio.get('$baseUrl$path', queryParameters: query), parser);

  Future<T> post<T>(
    String path, {
    Object? body,
    T Function(dynamic)? parser,
  }) =>
      _request<T>(() => _dio.post('$baseUrl$path', data: body), parser);

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() send,
    T Function(dynamic)? parser,
  ) async {
    try {
      final resp = await send();
      final json = resp.data as Map<String, dynamic>;
      if (json['code'] == 0) {
        final data = json['data'];
        return parser != null ? parser(data) : data as T;
      }
      throw ServerApiException(
        errorCode: json['error_code']?.toString() ?? 'UNKNOWN',
        message: json['message']?.toString() ?? '',
        statusCode: resp.statusCode,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw ServerApiException(
          errorCode: 'NETWORK',
          message: e.message ?? '',
          statusCode: null,
        );
      }
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        final code = body['error_code']?.toString() ?? 'UNKNOWN';
        final ex = ServerApiException(
          errorCode: code,
          message: body['message']?.toString() ?? '',
          statusCode: e.response?.statusCode,
        );
        if (code == 'TOKEN_EXPIRED' || code == 'EVICTED' || code == 'BANNED') {
          _authCallback?.call(code == 'EVICTED'
              ? AuthFailureKind.evicted
              : code == 'BANNED'
                  ? AuthFailureKind.banned
                  : AuthFailureKind.tokenExpired);
        }
        throw ex;
      }
      throw ServerApiException(
        errorCode: 'UNKNOWN',
        message: e.message ?? '',
        statusCode: e.response?.statusCode,
      );
    }
  }
}

/// error_code → 现有异常（查词/加词调用点使用；保留编排层分类语义）。
///
/// 映射表（对照服务端 error_code 契约）：
/// - `LLM_FATAL` / 未知错误码 → [LlmFatalException]（不可恢复，立即失败）
/// - `LLM_RECOVERABLE_EXHAUSTED` → [LlmRecoverableExhaustedException]
///   （可恢复但重试已耗尽，attempts=3 对齐现有编排层语义）
/// - `LLM_TIMEOUT` / `NETWORK` → [LlmTimeoutException]
///   （网络错误与服务端超时同语义，见类注释）
/// - `PIPELINE_BLOCKING` → [PipelineBlockingException]（结构性错误，阻塞流水线）
/// - `QUOTA_EXCEEDED` → [QuotaExceededException]
/// - `TOKEN_EXPIRED` / `EVICTED` / `BANNED` 不在此表：认证失败经
///   [ServerApiClient.setAuthCallback] 处理，落到 default 按致命错误。
Exception mapErrorCodeToException(ServerApiException e) {
  switch (e.errorCode) {
    case 'LLM_FATAL':
      return LlmFatalException(e.message);
    case 'LLM_RECOVERABLE_EXHAUSTED':
      return LlmRecoverableExhaustedException(e.message, cause: null, attempts: 3);
    case 'LLM_TIMEOUT':
      return LlmTimeoutException(e.message);
    case 'PIPELINE_BLOCKING':
      return PipelineBlockingException(e.message);
    case 'QUOTA_EXCEEDED':
      return QuotaExceededException(e.message);
    case 'NETWORK':
      return LlmTimeoutException(e.message);
    default:
      return LlmFatalException(e.message);
  }
}
