import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/data/monitoring/feishu_alert_sender.dart';
import 'package:contexta/domain/developer_alert_sender.dart';
import 'package:contexta/domain/error/app_error.dart';
import 'package:contexta/domain/time/time_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// FeishuAlertSender 测试：签名正确性 + 卡片内容 + 去重 + 业务码校验。
///
/// 对照 Kotlin FeishuAlertSender.kt：
/// - stringToSign = timestamp + "\n" + secret，HMAC-SHA256(空串) → Base64；
///   sign 拼进 URL query 前必须 URL 编码（+ / 会被飞书按 URL 标准破坏）
/// - timestamp = nowMillis/1000 - 30（防设备时钟超前被拒）
/// - 错误告警 5 分钟去重（同 类型_错误码_batchId）；batch ready 不去重
/// - 业务失败（HTTP 200 + code != 0）抛异常 → false；未配置静默跳过
///
/// 签名向量独立预计算（python hmac，非同源实现）：
/// ts=1785635970, secret="test-secret" → 074humqeTQexPSLarToi+fP0ZsY6HC/2j/rcZ/A6B7g=
const _kTestVectorSign = '074humqeTQexPSLarToi+fP0ZsY6HC/2j/rcZ/A6B7g=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAdapter adapter;
  late FeishuAlertSender sender;
  late _MutableTimeProvider time;

  FeishuAlertSender buildSender() {
    final dio = Dio()..httpClientAdapter = adapter;
    return FeishuAlertSender(
      timeProvider: time,
      webhookUrl: 'https://open.feishu.cn/open-apis/bot/v2/hook/test',
      signSecret: 'test-secret',
      dio: dio,
    );
  }

  setUp(() {
    time = _MutableTimeProvider(1785636000000);
    adapter = _RecordingAdapter(
      handler: (_) async => _okResponse('{"code":0}'),
    );
    sender = buildSender();
  });

  group('签名与 URL', () {
    test('timestamp 减 30 秒缓冲，sign 用预计算向量且 URL 编码', () async {
      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'api key invalid'),
        const ErrorContext(batchId: 7, articleId: 3, appVersion: 12, timestamp: 1785636000000),
      );

      expect(ok, isTrue);
      final req = adapter.requests.single;
      expect(req.uri.queryParameters['timestamp'], '1785635970');
      // 解码后 == 原始 base64 → 线上传输经过了 URL 编码
      expect(req.uri.queryParameters['sign'], _kTestVectorSign);
      expect(req.uri.toString(), contains('%2B')); // + 被编码，否则飞书解码为空格
    });

    test('webhook 未配置时静默跳过（不发请求，返回 true）', () async {
      sender = FeishuAlertSender(
        timeProvider: time,
        webhookUrl: '',
        signSecret: 'test-secret',
        dio: Dio()..httpClientAdapter = adapter,
      );

      final ok = await sender.sendStructuralError(
        const Structural(code: StructuralCode.illegalState, message: 'bug'),
        const ErrorContext(timestamp: 1785636000000),
      );

      expect(ok, isTrue);
      expect(adapter.requests, isEmpty);
    });

    test('secret 未配置时静默跳过', () async {
      sender = FeishuAlertSender(
        timeProvider: time,
        webhookUrl: 'https://x',
        signSecret: '',
        dio: Dio()..httpClientAdapter = adapter,
      );

      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'x'),
        const ErrorContext(timestamp: 1785636000000),
      );

      expect(ok, isTrue);
      expect(adapter.requests, isEmpty);
    });
  });

  group('卡片内容', () {
    test('LLM fatal 卡：标题/红色模板/错误码/消息/版本/Batch/Article/时间', () async {
      await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'api key invalid'),
        ErrorContext(
          batchId: 7,
          articleId: 3,
          appVersion: 12,
          timestamp: _localMillis(2026, 8, 1, 12, 0, 0),
        ),
      );

      final card = _cardOf(adapter.requests.single);
      expect(_titleOf(card), '🔴 Contexta LLM Fatal Error');
      expect(_templateOf(card), 'red');
      final texts = _elementTexts(card);
      expect(texts, contains('**错误码：**AUTH_FAILED'));
      expect(texts, contains('**消息：**api key invalid'));
      expect(texts, contains('**App 版本：**12'));
      expect(texts, contains('**Batch ID：**7'));
      expect(texts, contains('**Article ID：**3'));
      expect(texts, contains('**时间：**2026-08-01 12:00:00'));
    });

    test('结构错误卡：红色 + STRUCTURAL 错误码', () async {
      await sender.sendStructuralError(
        const Structural(code: StructuralCode.serializationError, message: 'parse failed'),
        const ErrorContext(timestamp: 1785636000000),
      );

      final card = _cardOf(adapter.requests.single);
      expect(_titleOf(card), '⚠️ Contexta Structural Error');
      expect(_templateOf(card), 'red');
      expect(_elementTexts(card), contains('**错误码：**SERIALIZATION_ERROR'));
      expect(_elementTexts(card), contains('**Batch ID：**N/A'));
    });

    test('文章失败卡：橙色 + 状态前缀', () async {
      await sender.sendArticleFailure(
        status: 'TIMEOUT',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'slow',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );

      final card = _cardOf(adapter.requests.single);
      expect(_titleOf(card), '🟡 Contexta Article TIMEOUT');
      expect(_templateOf(card), 'orange');
      expect(_elementTexts(card), contains('**错误码：**LLM_TIMEOUT'));
    });

    test('批次完成卡：绿色 + 批次信息，且不去重（两次都发）', () async {
      final ok1 = await sender.sendBatchReady(
        batchId: 9,
        articleCount: 4,
        batchGeneratedOn: '2026-08-01',
        batchDifficulty: 'medium',
        context: const ErrorContext(timestamp: 1785636000000),
      );
      final ok2 = await sender.sendBatchReady(
        batchId: 9,
        articleCount: 4,
        batchGeneratedOn: '2026-08-01',
        batchDifficulty: 'medium',
        context: const ErrorContext(timestamp: 1785636000000),
      );

      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(adapter.requests, hasLength(2));
      final card = _cardOf(adapter.requests.first);
      expect(_titleOf(card), '🟢 Contexta Batch Ready');
      expect(_templateOf(card), 'green');
      expect(_elementTexts(card),
          contains('**2026-08-01 · medium 批次已完成：**4 篇文章生成成功'));
    });

    test('错误消息截断 500 字符', () async {
      await sender.sendLlmFatalError(
        LlmFatal(code: LlmFatalCode.authFailed, message: 'x' * 600),
        const ErrorContext(timestamp: 1785636000000),
      );

      final texts = _elementTexts(_cardOf(adapter.requests.single));
      expect(texts.any((t) => t.contains('x' * 500)), isTrue);
      expect(texts.any((t) => t.contains('x' * 501)), isFalse);
    });
  });

  group('去重', () {
    test('5 分钟内同 batch + 同错误码只发一次（去重命中视为已通知）', () async {
      final ok1 = await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );
      // 3 分钟后：同一 dedupKey → 不再发请求，返回 true
      time.now = 1785636000000 + 3 * 60 * 1000;
      final ok2 = await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000 + 180000),
      );

      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(adapter.requests, hasLength(1));
    });

    test('超过 5 分钟窗口后重新发送', () async {
      await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );
      time.now = 1785636000000 + 6 * 60 * 1000;
      final ok = await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000 + 360000),
      );

      expect(ok, isTrue);
      expect(adapter.requests, hasLength(2));
    });

    test('不同错误码不互相去重', () async {
      await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );
      final ok = await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'SERVER_ERROR',
        errorMessage: 'b',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );

      expect(ok, isTrue);
      expect(adapter.requests, hasLength(2));
    });

    test('发送失败不记录去重时间 → 窗口内重试仍会再发', () async {
      adapter = _RecordingAdapter(
        handler: (_) async => _okResponse('{"code":19021,"msg":"sign match fail"}'),
      );
      sender = buildSender();

      final ok1 = await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );
      final ok2 = await sender.sendArticleFailure(
        status: 'FAILED',
        errorCode: 'LLM_TIMEOUT',
        errorMessage: 'a',
        context: const ErrorContext(batchId: 1, timestamp: 1785636000000),
      );

      expect(ok1, isFalse);
      expect(ok2, isFalse);
      expect(adapter.requests, hasLength(2));
    });
  });

  group('响应校验', () {
    test('HTTP 200 + code=0 → 成功', () async {
      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'x'),
        const ErrorContext(timestamp: 1785636000000),
      );
      expect(ok, isTrue);
    });

    test('HTTP 200 + 业务 code!=0（19021 签名失败）→ false', () async {
      adapter = _RecordingAdapter(
        handler: (_) async => _okResponse('{"code":19021,"msg":"sign match fail"}'),
      );
      sender = buildSender();

      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'x'),
        const ErrorContext(timestamp: 1785636000000),
      );
      expect(ok, isFalse);
    });

    test('HTTP 500 → false', () async {
      adapter = _RecordingAdapter(
        handler: (_) async => _okResponse('oops', statusCode: 500),
      );
      sender = buildSender();

      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'x'),
        const ErrorContext(timestamp: 1785636000000),
      );
      expect(ok, isFalse);
    });

    test('HTTP 200 + 非 JSON 响应体 → 按 HTTP 状态码判定成功', () async {
      adapter = _RecordingAdapter(
        handler: (_) async => _okResponse('<html>proxy intercept</html>'),
      );
      sender = buildSender();

      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'x'),
        const ErrorContext(timestamp: 1785636000000),
      );
      expect(ok, isTrue);
    });

    test('网络异常 → false（不影响主流程）', () async {
      adapter = _RecordingAdapter(
        handler: (_) async => throw DioException.connectionError(
          requestOptions: RequestOptions(path: ''),
          reason: 'no network',
        ),
      );
      sender = buildSender();

      final ok = await sender.sendLlmFatalError(
        const LlmFatal(code: LlmFatalCode.authFailed, message: 'x'),
        const ErrorContext(timestamp: 1785636000000),
      );
      expect(ok, isFalse);
    });
  });
}

ResponseBody _okResponse(String body, {int statusCode = 200}) =>
    ResponseBody.fromString(body, statusCode);

Map<String, Object?> _cardOf(RequestOptions req) {
  final body = jsonDecode(req.data as String) as Map<String, Object?>;
  return body['card'] as Map<String, Object?>;
}

Map<String, Object?> _headerOf(Map<String, Object?> card) =>
    card['header'] as Map<String, Object?>;

String _titleOf(Map<String, Object?> card) =>
    (_headerOf(card)['title'] as Map<String, Object?>)['content'] as String;

String _templateOf(Map<String, Object?> card) =>
    _headerOf(card)['template'] as String;

List<String> _elementTexts(Map<String, Object?> card) {
  final elements = card['elements'] as List<Object?>;
  return [
    for (final e in elements)
      ((e as Map<String, Object?>)['text'] as Map<String, Object?>)['content']
          as String,
  ];
}

/// 构造与机器时区无关的本地时间（卡片时间断言确定）。
int _localMillis(int y, int m, int d, int hh, int mm, int ss) =>
    DateTime(y, m, d, hh, mm, ss).millisecondsSinceEpoch;

class _MutableTimeProvider implements TimeProvider {
  _MutableTimeProvider(this.now);

  int now;

  @override
  int nowMillis() => now;

  @override
  String nowDateTimeString() => '2026-08-01T12:00:00+08:00';

  @override
  String todayDateString() => '2026-08-01';

  @override
  String nextDateString() => '2026-08-02';
}

/// 录制型 dio adapter：捕获请求（URL/body），返回 canned 响应。
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.handler});

  Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];
  final List<String> requestBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());
      requestBodies.add(utf8.decode(bytes));
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
