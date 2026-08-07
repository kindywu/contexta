import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../domain/developer_alert_sender.dart';
import '../../domain/error/app_error.dart';
import '../../domain/time/time_provider.dart';

/// 飞书自定义机器人 webhook 告警发送器（对照 Kotlin FeishuAlertSender.kt）。
///
/// - 错误类告警 5 分钟去重（key = 类型_错误码_batchId）；批次完成通知不去重
/// - 签名：stringToSign = timestamp + "\n" + secret，以其为 HMAC-SHA256 key
///   对空串签名，Base64 编码；拼进 URL query 前必须 URL 编码（+ / 会被破坏）
/// - 飞书业务失败时 HTTP 仍可能 200，必须解析响应体 business code：非 0
///   （如 19021 签名失败）抛异常 → 调用方返回 false → 不回写 notified_at
/// - webhook/secret 未配置时静默跳过（Log 提示），不抛异常
class FeishuAlertSender implements DeveloperAlertSender {
  FeishuAlertSender({
    required this.timeProvider,
    required this.webhookUrl,
    required this.signSecret,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  static const int dedupWindowMs = 5 * 60 * 1000;

  final TimeProvider timeProvider;
  final String webhookUrl;
  final String signSecret;
  final Dio _dio;

  final Map<String, int> _lastSentMap = {};

  @override
  Future<bool> sendLlmFatalError(LlmFatal error, ErrorContext context) {
    return _sendError(
      dedupPrefix: 'LLMFATAL',
      errorCode: error.code.toDbValue(),
      errorMessage: error.message,
      context: context,
      title: '🔴 Contexta LLM Fatal Error',
      templateColor: 'red',
    );
  }

  @override
  Future<bool> sendStructuralError(Structural error, ErrorContext context) {
    return _sendError(
      dedupPrefix: 'STRUCTURAL',
      errorCode: error.code.toDbValue(),
      errorMessage: error.message,
      context: context,
      title: '⚠️ Contexta Structural Error',
      templateColor: 'red',
    );
  }

  @override
  Future<bool> sendArticleFailure({
    required String status,
    required String errorCode,
    required String errorMessage,
    required ErrorContext context,
  }) {
    // 5 分钟内同 batch + 同 errorCode 去重，避免刷屏
    return _sendError(
      dedupPrefix: 'ARTICLE_$status',
      errorCode: errorCode,
      errorMessage: errorMessage,
      context: context,
      title: '🟡 Contexta Article $status',
      templateColor: 'orange',
    );
  }

  @override
  Future<bool> sendBatchReady({
    required int batchId,
    required int articleCount,
    required String? batchGeneratedOn,
    required String? batchDifficulty,
    required ErrorContext context,
  }) {
    // 批次完成通知不做去重——每个批次只发一次
    // （重复补发由 ready_notified_at 幂等标记防住）
    return _send(
      () => _buildSuccessCard(
        title: '🟢 Contexta Batch Ready',
        batchId: batchId,
        articleCount: articleCount,
        batchGeneratedOn: batchGeneratedOn,
        batchDifficulty: batchDifficulty,
        context: context,
      ),
    );
  }

  Future<bool> _sendError({
    required String dedupPrefix,
    required String errorCode,
    required String errorMessage,
    required ErrorContext context,
    required String title,
    required String templateColor,
  }) {
    final dedupKey = '${dedupPrefix}_${errorCode}_${context.batchId}';
    final lastSent = _lastSentMap[dedupKey];
    if (lastSent != null &&
        timeProvider.nowMillis() - lastSent < dedupWindowMs) {
      // 去重命中 = 该告警近期已发过，视为已通知
      return Future.value(true);
    }

    return _send(
      () => _buildErrorCard(
        title: title,
        templateColor: templateColor,
        errorCode: errorCode,
        errorMessage: errorMessage,
        context: context,
      ),
      onSuccess: () => _lastSentMap[dedupKey] = timeProvider.nowMillis(),
    );
  }

  Future<bool> _send(
    String Function() buildCard, {
    void Function()? onSuccess,
  }) async {
    try {
      final message = buildCard();
      await _sendToFeishu(message);
      onSuccess?.call();
      return true;
    } catch (e) {
      // 发送失败不影响主流程；返回 false 让调用方保留补发标记
      return false;
    }
  }

  Map<String, Object> _header(String title, String templateColor) {
    return {
      'header': {
        'title': {'tag': 'plain_text', 'content': title},
        'template': templateColor,
      },
    };
  }

  Map<String, Object> _div(String content) {
    return {
      'tag': 'div',
      'text': {'tag': 'lark_md', 'content': content},
    };
  }

  String _buildErrorCard({
    required String title,
    required String templateColor,
    required String errorCode,
    required String errorMessage,
    required ErrorContext context,
  }) {
    final card = {
      'msg_type': 'interactive',
      'card': {
        ..._header(title, templateColor),
        'elements': [
          _div('**错误码：**$errorCode'),
          _div('**消息：**${_truncate(errorMessage, 500)}'),
          _div('**App 版本：**${context.appVersion}'),
          _div('**Batch ID：**${context.batchId ?? 'N/A'}'),
          _div('**Article ID：**${context.articleId ?? 'N/A'}'),
          _div('**时间：**${_formatTime(context.timestamp)}'),
        ],
      },
    };
    return jsonEncode(card);
  }

  String _buildSuccessCard({
    required String title,
    required int batchId,
    required int articleCount,
    required String? batchGeneratedOn,
    required String? batchDifficulty,
    required ErrorContext context,
  }) {
    final card = {
      'msg_type': 'interactive',
      'card': {
        ..._header(title, 'green'),
        'elements': [
          _div('**${batchGeneratedOn ?? '?'} · ${batchDifficulty ?? '?'} '
              '批次已完成：**$articleCount 篇文章生成成功'),
          _div('**Batch ID：**$batchId'),
          _div('**时间：**${_formatTime(context.timestamp)}'),
        ],
      },
    };
    return jsonEncode(card);
  }

  String _formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _truncate(String s, int max) =>
      s.length > max ? s.substring(0, max) : s;

  Future<void> _sendToFeishu(String message) async {
    if (webhookUrl.isEmpty) {
      stderr.writeln('FeishuAlertSender: FEISHU_WEBHOOK_URL not configured');
      return;
    }
    if (signSecret.isEmpty) {
      stderr.writeln('FeishuAlertSender: FEISHU_SIGN_SECRET not configured');
      return;
    }

    // 减 30 秒缓冲，防止设备时钟比飞书服务器快导致 timestamp 被拒
    final timestamp = (timeProvider.nowMillis() ~/ 1000 - 30).toString();
    final sign = _generateSign(timestamp, signSecret);
    // ⚠️ base64 签名可能含 +（也可能含 /），拼进 URL query 必须 URL 编码：
    // 飞书按 URL 标准把 + 解码为空格，未编码的签名会被破坏 → 19021 sign match fail
    final encodedSign = Uri.encodeQueryComponent(sign);
    final fullUrl = '$webhookUrl?timestamp=$timestamp&sign=$encodedSign';

    final response = await _dio.post<String>(
      fullUrl,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.plain,
        // 非 2xx 不抛 DioException：需自己读错误响应体（对照 Kotlin
        // HttpURLConnection 读取 errorStream）
        validateStatus: (_) => true,
      ),
      data: message,
    );
    final responseBody = response.data ?? '';
    if (response.statusCode! < 200 || response.statusCode! >= 300) {
      throw HttpException('Feishu API returned ${response.statusCode}: $responseBody');
    }
    // ⚠️ 飞书 Webhook 业务失败时 HTTP 仍返回 200，必须解析响应体的业务 code：
    // code != 0（如 19021 签名失败 / 19001 参数错误）视为发送失败，抛异常
    // → 调用方返回 false → 不回写 notified_at → 下次启动补发重试
    final businessCode = _parseBusinessCode(responseBody);
    if (businessCode != null && businessCode != 0) {
      throw HttpException('Feishu business error code=$businessCode, body=$responseBody');
    }
  }

  int? _parseBusinessCode(String responseBody) {
    try {
      final code = jsonDecode(responseBody)['code'];
      if (code is int && code >= 0) return code;
      return null;
    } catch (_) {
      // 非 JSON 响应体（如网络代理拦截页），无法解析业务码 → 交给 HTTP 状态码判断
      return null;
    }
  }

  /// 飞书签名算法：
  /// 1. stringToSign = timestamp + "\n" + secret
  /// 2. 以 stringToSign 为密钥，对空字符串做 HMAC-SHA256
  /// 3. Base64 编码结果
  ///
  /// ⚠️ key=stringToSign, data=""（非直觉：timestamp+secret 是密钥而非数据）
  String _generateSign(String timestamp, String secret) {
    final stringToSign = '$timestamp\n$secret';
    final hmac = Hmac(sha256, utf8.encode(stringToSign));
    return base64Encode(hmac.convert(utf8.encode('')).bytes);
  }
}
