import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../domain/error/llm_exceptions.dart';
import '../../domain/error/pipeline_blocking_exception.dart';
import '../../domain/llm_client.dart';
import '../../domain/llm_error_classifier.dart';
import 'deepseek_api.dart';
import 'dto/chat_request.dart';

/// 可恢复错误 → 需要等待后重试的内部信号（由 [LlmCaller.call] 捕获处理）。
class _RetrySignal implements Exception {
  _RetrySignal(this.waitMs);

  final int waitMs;
}

/// 统一 LLM 调用器，带重试逻辑（对照 Kotlin LlmCaller.kt）。
///
/// - 可恢复错误（网络、429、5xx、坏 JSON）：重试至多 [AppConfig.llmMaxRetries] 次
/// - 不可恢复错误（401、403、400）：立即抛出 [LlmFatalException]
/// - 结构性错误（DB、序列化）：抛出 [PipelineBlockingException]
///
/// 总预算超时（[LlmClient.call] 的 [timeoutMs]，缺省 LLM_TIMEOUT_MS）：
/// 类比 Kotlin `withTimeoutOrNull` 包裹整个重试循环——总预算耗尽整体放弃并抛
/// [LlmTimeoutException]，而不是取消调用方（避免同批次后续文章无法继续生成）。
/// 每次尝试、每次退避等待都从总预算中扣除（逐字对齐 Kotlin 语义）。
///
/// 测试注入：[sleeper] 替代真实 [Future.delayed]；[cancelToken] 提供外部取消
/// 信号（Kotlin 语义的协程取消在 Dart 中以 CancelToken 对应，取消立即传播，
/// 不会被误分类为重试）。
class LlmCaller implements LlmClient {
  LlmCaller(
    this._api, {
    Future<void> Function(Duration delay)? sleeper,
    this.cancelToken,
  }) : _sleeper = sleeper ?? Future.delayed;

  final DeepSeekApi _api;
  final Future<void> Function(Duration delay) _sleeper;

  /// 外部取消信号（Kotlin: CancellationException；Dart: CancelToken）。
  /// 内部类字段公开仅为构造注入；取消时立即传播，不被误分类为重试。
  final CancelToken? cancelToken;

  @override
  Future<LlmResult> call(
    String systemPrompt,
    String userPrompt, {
    int? timeoutMs,
  }) async {
    final budget = timeoutMs ?? AppConfig.llmTimeoutMs;
    var retryCount = 0;
    final elapsed = Stopwatch()..start();

    while (true) {
      final remaining = budget - elapsed.elapsedMilliseconds;
      if (remaining <= 0) {
        throw LlmTimeoutException('Timed out waiting for $budget ms');
      }
      try {
        final content =
            await _attemptOnce(systemPrompt, userPrompt, remaining, retryCount);
        return LlmResult(content: content, retryCount: retryCount);
      } on _RetrySignal catch (signal) {
        retryCount++;
        // 退避/Retry-After 等待也计入总预算（Kotlin delay 在 withTimeoutOrNull 内）
        final waitRemaining = budget - elapsed.elapsedMilliseconds;
        if (waitRemaining <= 0) {
          throw LlmTimeoutException('Timed out waiting for $budget ms');
        }
        await _sleeper(Duration(milliseconds: signal.waitMs.clamp(0, waitRemaining).toInt()));
      } on TimeoutException {
        throw LlmTimeoutException('Timed out waiting for $budget ms');
      }
    }
  }

  /// 单次尝试（含分类与重试判定）：
  /// 成功返回内容；总预算内超时抛 TimeoutException（由 call 转 LlmTimeoutException）；
  /// 结构性/致命错误立即抛出；可恢复错误抛 [_RetrySignal] 请求重试。
  Future<String> _attemptOnce(
    String systemPrompt,
    String userPrompt,
    int timeoutMs,
    int retryCount,
  ) async {
    debugPrint('[LlmCaller] attempt #${retryCount + 1}: POST chat/completions model=${AppConfig.deepSeekModel} baseUrl=${AppConfig.deepSeekBaseUrl} keyLen=${AppConfig.deepSeekApiKey.length}');
    try {
      final response = await _api
          .chatCompletion(
            ChatCompletionRequest(
              model: AppConfig.deepSeekModel,
              messages: [
                ChatMessage(role: 'system', content: systemPrompt),
                ChatMessage(role: 'user', content: userPrompt),
              ],
            ),
            cancelToken: cancelToken,
          )
          .timeout(Duration(milliseconds: timeoutMs));
      final content = response.choices.firstOrNull?.message.content;
      debugPrint('[LlmCaller] attempt #${retryCount + 1}: response OK contentLen=${content?.length} choices=${response.choices.length}');
      if (content == null) {
        // Kotlin: 空 choices 抛 IllegalStateException("Empty response from LLM")，
        // 无 HTTP code → 分类为可恢复 → 重试
        throw Exception('Empty response from LLM');
      }
      return content;
    } on TimeoutException {
      debugPrint('[LlmCaller] attempt #${retryCount + 1}: TIMEOUT after ${timeoutMs}ms');
      rethrow;
    } catch (e) {
      // 取消信号立即传播：不能当作可恢复错误重试（Kotlin: CancellationException）
      if (e is DioException && e.type == DioExceptionType.cancel) {
        rethrow;
      }
      final httpCode = _extractHttpCode(e);
      final classified = LlmErrorClassifier.classify(httpCode, e);
      debugPrint('[LlmCaller] attempt #${retryCount + 1} FAILED httpCode=$httpCode classified=${classified.runtimeType} err=$e');
      switch (classified) {
        case StructuralError():
          throw PipelineBlockingException(
            'Structural error: ${classified.cause}',
            cause: classified.cause,
          );
        case FatalError():
          throw LlmFatalException(
            'Non-recoverable LLM error: ${classified.cause}',
            cause: classified.cause,
          );
        case RecoverableError():
          if (retryCount >= AppConfig.llmMaxRetries) {
            // 本次为最后一次允许的尝试，失败 → 重试耗尽
            throw LlmRecoverableExhaustedException(
              'LLM call failed after ${AppConfig.llmMaxRetries} retries: ${classified.cause}',
              cause: classified.cause,
              attempts: retryCount,
            );
          }
          throw _RetrySignal(_waitMillis(classified.retryAfterSeconds, retryCount + 1));
      }
    }
  }

  /// 等待时长：429 用 Retry-After（封顶 MAX_RETRY_AFTER_SECONDS），
  /// 否则指数退避 2000ms × 2^(n-1) 封顶 10s（Kotlin 逐字移植）。
  int _waitMillis(int? retryAfterSeconds, int attemptNumber) {
    if (retryAfterSeconds != null) {
      return retryAfterSeconds.clamp(0, AppConfig.llmMaxRetryAfterSeconds).toInt() * 1000;
    }
    return (2000 * (1 << (attemptNumber - 1))).clamp(0, 10000).toInt();
  }

  /// 提取 HTTP 状态码（Kotlin 正则 `HTTP (\d+)`）。
  /// 扩展：dio 的 HTTP 错误是 DioException（code 在 response.statusCode 而非
  /// message 文本中），直接读取——等价 Retrofit HttpException message 里
  /// 内嵌的 "HTTP <code>"。
  int? _extractHttpCode(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) return statusCode;
    }
    final match = RegExp(r'HTTP (\d+)').firstMatch(error.toString());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
