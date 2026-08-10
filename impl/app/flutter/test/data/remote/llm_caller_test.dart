import 'dart:async';
import 'dart:io';

import 'package:contexta/core/config/app_config.dart';
import 'package:contexta/data/remote/deepseek_api.dart';
import 'package:contexta/data/remote/dto/chat_request.dart';
import 'package:contexta/data/remote/dto/chat_response.dart';
import 'package:contexta/data/remote/llm_caller.dart';
import 'package:contexta/domain/error/llm_exceptions.dart';
import 'package:contexta/domain/error/pipeline_blocking_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 移植 Android LlmCallerTest.kt（3 个超时/取消用例）+ 分类器集成用例
/// （401 立即失败 / 429 Retry-After / 退避重试 / Constraint 结构性阻塞）。
///
/// Kotlin 的协程取消（CancellationException）在 Dart 中以 dio CancelToken
/// 对应：外部取消 → DioException(cancel) 立即传播，不被误分类重试。
class _FakeApi implements DeepSeekApi {
  _FakeApi();

  /// (request) -> 响应或抛错；返回挂起 future 即模拟网络挂起。
  Future<ChatCompletionResponse> Function(ChatCompletionRequest request)? handler;

  int calls = 0;

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    final h = handler;
    if (h == null) {
      throw StateError('fake api: no handler set');
    }
    final result = h(request);
    final token = cancelToken;
    if (token == null) return result;
    // 外部取消 → 抛 DioException(cancel)（对齐 dio 真实行为）
    final completer = Completer<ChatCompletionResponse>();
    result.then(completer.complete, onError: completer.completeError);
    token.whenCancel.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        ));
      }
    });
    return completer.future;
  }
}

/// 永不完成的请求（模拟网络挂起：不触发假成功/假失败）。
Future<ChatCompletionResponse> _hang(ChatCompletionRequest _) =>
    Completer<ChatCompletionResponse>().future;

const _system = 'You are a helpful assistant.';
const _user = 'Hello';

ChatCompletionResponse _ok(String content) => ChatCompletionResponse(
      choices: [Choice(message: ChatResponseMessage(content: content))],
    );

void main() {
  group('LlmCaller 超时与取消（对照 Kotlin LlmCallerTest.kt）', () {
    test('网络调用挂起超时后抛 LlmTimeoutException', () async {
      final api = _FakeApi()..handler = _hang;
      final caller = LlmCaller(api);

      // 关键验证点：总预算超时 → LlmTimeoutException
      //（而非误分类为 RecoverableExhausted / 吞掉后重试）
      await expectLater(
        caller.call(_system, _user, timeoutMs: 500),
        throwsA(isA<LlmTimeoutException>()),
      );
      expect(api.calls, 1);
    });

    test('超时发生在最后一次尝试时 仍按 LLM_TIMEOUT 分类', () async {
      // 前 MAX_RETRIES 次尝试：HTTP 500（可恢复，触发退避重试）
      // 最后一次尝试：挂起远超剩余预算，总预算超时
      var attempts = 0;
      final api = _FakeApi()
        ..handler = (request) async {
          attempts++;
          if (attempts <= AppConfig.llmMaxRetries) {
            throw const SocketException('HTTP 500 Server Error');
          }
          return _hang(request);
        };
      final caller = LlmCaller(api, sleeper: (_) async {});

      await expectLater(
        caller.call(_system, _user, timeoutMs: 20),
        throwsA(isA<LlmTimeoutException>()),
      );
      expect(api.calls, AppConfig.llmMaxRetries + 1);
    });

    test('真正的外部取消传播取消信号而非误分类', () async {
      // 前 MAX_RETRIES 次尝试失败后，最后一次尝试挂起（等待被取消）
      final lastAttemptStarted = Completer<void>();
      var attempts = 0;
      final api = _FakeApi()
        ..handler = (request) async {
          attempts++;
          if (attempts <= AppConfig.llmMaxRetries) {
            throw const SocketException('HTTP 500 Server Error');
          }
          lastAttemptStarted.complete();
          return _hang(request);
        };
      final cancelToken = CancelToken();
      final caller = LlmCaller(api, sleeper: (_) async {}, cancelToken: cancelToken);

      final callFuture = caller.call(_system, _user, timeoutMs: 60000);
      await lastAttemptStarted.future; // 最后一次尝试已挂起，此时取消
      cancelToken.cancel();

      // 修复后：取消传播为 DioException(cancel)（Kotlin: CancellationException），
      // 而非被 catch 吞掉 → retryCount++ > MAX → 误报 RecoverableExhausted
      await expectLater(callFuture, throwsA(isA<DioException>()));
      expect(attempts, AppConfig.llmMaxRetries + 1);
    });
  });

  group('LlmCaller 分类与重试（计划补充用例）', () {
    test('首次调用成功返回 content 与 retryCount 0', () async {
      final api = _FakeApi()..handler = ((_) async => _ok('hi'));
      final caller = LlmCaller(api);

      final result = await caller.call(_system, _user);
      expect(result.content, 'hi');
      expect(result.retryCount, 0);
      expect(api.calls, 1);
    });

    test('401 立即抛 LlmFatalException 不重试', () async {
      final api = _FakeApi()
        ..handler = ((_) async => throw Exception('HTTP 401 Unauthorized'));
      final caller = LlmCaller(api);

      await expectLater(
        caller.call(_system, _user),
        throwsA(isA<LlmFatalException>()),
      );
      expect(api.calls, 1);
    });

    test('429 Retry-After 重试，封顶后抛 RecoverableExhausted', () async {
      final waits = <Duration>[];
      final api = _FakeApi()
        ..handler = ((_) async =>
            throw Exception('HTTP 429 Too Many Requests — Retry-After: 120'));
      final caller = LlmCaller(api, sleeper: (d) async => waits.add(d));

      await expectLater(
        caller.call(_system, _user),
        throwsA(isA<LlmRecoverableExhaustedException>()
            .having((e) => e.attempts, 'attempts', AppConfig.llmMaxRetries)),
      );
      expect(api.calls, AppConfig.llmMaxRetries + 1);
      // Retry-After 120 被 MAX_RETRY_AFTER_SECONDS 封顶
      expect(waits, [
        for (var i = 0; i < AppConfig.llmMaxRetries; i++)
          Duration(seconds: AppConfig.llmMaxRetryAfterSeconds),
      ]);
    });

    test('可恢复错误指数退避重试，最终成功后返回重试次数', () async {
      final waits = <Duration>[];
      var attempts = 0;
      final api = _FakeApi()
        ..handler = ((_) async {
          attempts++;
          if (attempts <= AppConfig.llmMaxRetries) {
            throw const SocketException('Connection refused');
          }
          return _ok('ok');
        });
      final caller = LlmCaller(api, sleeper: (d) async => waits.add(d));

      final result = await caller.call(_system, _user);
      expect(result.content, 'ok');
      expect(result.retryCount, AppConfig.llmMaxRetries);
      expect(api.calls, AppConfig.llmMaxRetries + 1);
      // 指数退避：2000ms × 2^(n-1)，封顶 10s → 2s、4s、8s
      expect(waits, [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
      ]);
    });

    test('message 含 Constraint 抛 PipelineBlockingException 立即阻塞', () async {
      final api = _FakeApi()
        ..handler = ((_) async => throw Exception('SQLiteException: Constraint failed'));
      final caller = LlmCaller(api);

      await expectLater(
        caller.call(_system, _user),
        throwsA(isA<PipelineBlockingException>()),
      );
      expect(api.calls, 1);
    });

    test('LLM 返回空 choices 视为可恢复错误重试后成功', () async {
      var attempts = 0;
      final api = _FakeApi()
        ..handler = ((_) async {
          attempts++;
          if (attempts == 1) return const ChatCompletionResponse();
          return _ok('ok');
        });
      final caller = LlmCaller(api, sleeper: (_) async {});

      final result = await caller.call(_system, _user);
      expect(result.content, 'ok');
      expect(api.calls, 2);
    });
  });
}
