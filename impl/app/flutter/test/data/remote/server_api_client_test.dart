import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/domain/error/llm_exceptions.dart';
import 'package:contexta/domain/error/pipeline_blocking_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// ServerApiClient 测试：envelope 解包 / 认证拦截 / error_code → 异常映射。
///
/// 用自定义 HttpClientAdapter 替换真实网络——请求仍走 dio 完整管线
/// （拦截器 → 适配器），因此 Bearer 头注入、非 2xx 转 DioException、
/// JSON 解码等行为与生产一致。
class _StubAdapter implements HttpClientAdapter {
  /// (options) -> 响应体；抛 DioException 模拟网络错误。
  Future<ResponseBody> Function(RequestOptions options) handler = _unset;

  /// 最近一次进入适配器的请求（断言 URL / 头 / 方法 / 参数）。
  RequestOptions? lastRequest;

  static Future<ResponseBody> _unset(RequestOptions _) =>
      throw StateError('stub adapter: handler 未设置');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int statusCode, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );

(ServerApiClient, _StubAdapter) _makeClient({
  Future<String?> Function()? tokenProvider,
  void Function(AuthFailureKind kind)? onAuth,
}) {
  final adapter = _StubAdapter();
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  final client = ServerApiClient(
    dio,
    baseUrl: 'https://api.example.com',
    tokenProvider: tokenProvider ?? () async => null,
  );
  if (onAuth != null) {
    client.setAuthCallback(onAuth);
  }
  return (client, adapter);
}

void main() {
  group('ServerApiClient 成功路径（envelope 解包）', () {
    test('get：code==0 解包 data（Map），URL/query 原样转发', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'name': 'world'},
          });

      final result =
          await client.get<Map<String, dynamic>>('/v1/hello', query: {'lang': 'en'});

      expect(result['name'], 'world');
      expect(adapter.lastRequest!.uri.path, '/v1/hello');
      expect(adapter.lastRequest!.uri.queryParameters['lang'], 'en');
    });

    test('post：code==0 解包 data，body 原样转发', () async {
      final (client, adapter) = _makeClient();
      final body = {'phone': '13800000000'};
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'id': 42},
          });

      final result = await client.post<Map<String, dynamic>>('/api/v1/login', body: body);

      expect(result['id'], 42);
      expect(adapter.lastRequest!.method, 'POST');
      expect(adapter.lastRequest!.data, body);
    });

    test('parser 自定义：data 经 parser 转换', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'name': 'world'},
          });

      final name = await client.get<String>(
        '/v1/hello',
        parser: (data) => (data as Map<String, dynamic>)['name'] as String,
      );

      expect(name, 'world');
    });
  });

  group('ServerApiClient 错误路径（非 2xx + error_code）', () {
    test('401 TOKEN_EXPIRED → ServerApiException + authCallback(tokenExpired)', () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(401, {
            'code': 401,
            'message': 'token expired',
            'error_code': 'TOKEN_EXPIRED',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'TOKEN_EXPIRED')
            .having((e) => e.message, 'message', 'token expired')
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(authCalls, [AuthFailureKind.tokenExpired]);
    });

    test('401 EVICTED → ServerApiException + authCallback(evicted)', () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(401, {
            'code': 401,
            'message': 'evicted',
            'error_code': 'EVICTED',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'EVICTED')),
      );
      expect(authCalls, [AuthFailureKind.evicted]);
    });

    test('403 BANNED → ServerApiException + authCallback(banned)', () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(403, {
            'code': 403,
            'message': 'banned',
            'error_code': 'BANNED',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'BANNED')
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
      expect(authCalls, [AuthFailureKind.banned]);
    });

    test('502 LLM_RECOVERABLE_EXHAUSTED → ServerApiException，不触发 authCallback', () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(502, {
            'code': 502,
            'message': 'llm exhausted',
            'error_code': 'LLM_RECOVERABLE_EXHAUSTED',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'LLM_RECOVERABLE_EXHAUSTED')),
      );
      expect(authCalls, isEmpty);
    });

    test('400 QUOTA_EXCEEDED → ServerApiException，不触发 authCallback', () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(400, {
            'code': 400,
            'message': 'quota exceeded',
            'error_code': 'QUOTA_EXCEEDED',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'QUOTA_EXCEEDED')
            .having((e) => e.message, 'message', 'quota exceeded')),
      );
      expect(authCalls, isEmpty);
    });

    test('网络错误（connectionError）→ ServerApiException(NETWORK)', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'Connection refused',
        );
      };

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'NETWORK')
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });

    test('发送超时（sendTimeout）→ ServerApiException(NETWORK)', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.sendTimeout,
          message: 'send timeout',
        );
      };

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'NETWORK')),
      );
    });

    test('2xx + code!=0 → ServerApiException（envelope 业务错误，不触发 authCallback）',
        () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(200, {
            'code': 1001,
            'message': 'bad param',
            'error_code': 'BAD_PARAM',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'BAD_PARAM')
            .having((e) => e.message, 'message', 'bad param')
            .having((e) => e.statusCode, 'statusCode', 200)),
      );
      expect(authCalls, isEmpty);
    });
  });

  group('ServerApiClient 解包防御（200 但响应畸形）', () {
    test('200 + HTML body（非 JSON 对象）→ ServerApiException(UNKNOWN)，而非 TypeError', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async => ResponseBody.fromString(
            '<html><body>gateway error</body></html>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html; charset=utf-8'],
            },
          );

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'UNKNOWN')),
      );
    });

    test('200 + code==0 + data 类型不符（数组）→ ServerApiException(UNKNOWN)', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': [1, 2, 3],
          });

      await expectLater(
        client.get<Map<String, dynamic>>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'UNKNOWN')),
      );
    });

    test('200 + code==0 + data null → ServerApiException(UNKNOWN)', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': null,
          });

      await expectLater(
        client.get<Map<String, dynamic>>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'UNKNOWN')),
      );
    });
  });

  group('ServerApiClient 认证拦截', () {
    test('Bearer 头自动附加（tokenProvider 返回值）', () async {
      final (client, adapter) = _makeClient(tokenProvider: () async => 'tok-123');
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'ok': true},
          });

      await client.get<dynamic>('/v1/hello');

      expect(adapter.lastRequest!.headers['Authorization'], 'Bearer tok-123');
    });

    test('tokenProvider 返回 null → 不附加 Authorization 头', () async {
      final (client, adapter) = _makeClient();
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'ok': true},
          });

      await client.get<dynamic>('/v1/hello');

      expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
    });

    test('并发两个 401 → authCallback 只触发 1 次（按 kind 去重）', () async {
      final authCalls = <AuthFailureKind>[];
      final (client, adapter) = _makeClient(onAuth: authCalls.add);
      adapter.handler = (options) async => _json(401, {
            'code': 401,
            'message': 'token expired',
            'error_code': 'TOKEN_EXPIRED',
          });

      await expectLater(
        Future.wait([
          client.get<dynamic>('/v1/hello'),
          client.get<dynamic>('/v1/hello'),
        ]),
        throwsA(isA<ServerApiException>()),
      );

      expect(authCalls, [AuthFailureKind.tokenExpired]);
    });

    test('authCallback 抛异常 → 不吞掉原始 ServerApiException', () async {
      final (client, adapter) = _makeClient(
        onAuth: (_) => throw StateError('callback boom'),
      );
      adapter.handler = (options) async => _json(401, {
            'code': 401,
            'message': 'token expired',
            'error_code': 'TOKEN_EXPIRED',
          });

      await expectLater(
        client.get<dynamic>('/v1/hello'),
        throwsA(isA<ServerApiException>()
            .having((e) => e.errorCode, 'errorCode', 'TOKEN_EXPIRED')),
      );
    });
  });

  group('mapErrorCodeToException 全表断言', () {
    ServerApiException se(String code) =>
        ServerApiException(errorCode: code, message: 'msg-$code');

    test('error_code → 现有异常映射（含细节）', () {
      final exhausted =
          mapErrorCodeToException(se('LLM_RECOVERABLE_EXHAUSTED'))
              as LlmRecoverableExhaustedException;
      expect(exhausted.attempts, 3);
      expect(exhausted.cause, isNull);
      expect(exhausted.message, 'msg-LLM_RECOVERABLE_EXHAUSTED');

      expect(mapErrorCodeToException(se('LLM_FATAL')), isA<LlmFatalException>());
      expect(mapErrorCodeToException(se('LLM_TIMEOUT')), isA<LlmTimeoutException>());
      expect(
        mapErrorCodeToException(se('PIPELINE_BLOCKING')),
        isA<PipelineBlockingException>(),
      );
      expect(
        mapErrorCodeToException(se('QUOTA_EXCEEDED')),
        isA<QuotaExceededException>(),
      );
      // 网络错误与服务端超时同语义 → LlmTimeoutException
      expect(mapErrorCodeToException(se('NETWORK')), isA<LlmTimeoutException>());
    });

    test('认证类错误码 / 未知错误码 → 保守致命（LlmFatalException）', () {
      // TOKEN_EXPIRED/EVICTED/BANNED 走 authCallback，映射表按致命错误处理
      expect(mapErrorCodeToException(se('TOKEN_EXPIRED')), isA<LlmFatalException>());
      expect(mapErrorCodeToException(se('EVICTED')), isA<LlmFatalException>());
      expect(mapErrorCodeToException(se('BANNED')), isA<LlmFatalException>());
      expect(mapErrorCodeToException(se('UNKNOWN')), isA<LlmFatalException>());
    });
  });
}
