import 'package:contexta/data/remote/deepseek_api.dart';
import 'package:contexta/data/remote/dto/chat_request.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 DioDeepSeekApi 的 baseUrl 拼接：
/// dio 的 uri getter 是 `baseUrl + path` 直接拼接（options.dart:672），
/// baseUrl 缺尾斜杠时 https://api.deepseek.com + v1/chat/completions →
/// https://api.deepseek.comv1/...（主机名被污染，DNS 解析失败）。
/// 构造时兜底补斜杠，与 Kotlin NetworkModule 默认值（带尾斜杠）对齐。
void main() {
  test('baseUrl 缺尾斜杠时自动补齐（与 Kotlin 默认值对齐）', () async {
    late Uri captured;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ),
    );
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        captured = options.uri;
        handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.cancel),
        );
      },
    ));

    final api = DioDeepSeekApi(dio, baseUrl: 'https://api.deepseek.com');
    expect(dio.options.baseUrl, 'https://api.deepseek.com/',
        reason: '构造时兜底补尾斜杠');

    await expectLater(
      api.chatCompletion(ChatCompletionRequest(
        model: 'deepseek-v4-flash',
        messages: const [],
      )),
      throwsA(isA<DioException>()),
    );

    expect(captured.toString(), 'https://api.deepseek.com/v1/chat/completions',
        reason: 'URL 拼接必须是 api.deepseek.com/v1/...，不能是 api.deepseek.comv1');
  });

  test('baseUrl 已带尾斜杠时不重复拼接', () {
    final dio = Dio(BaseOptions());
    DioDeepSeekApi(dio, baseUrl: 'https://api.deepseek.com/');
    expect(dio.options.baseUrl, 'https://api.deepseek.com/');
  });
}
