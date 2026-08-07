import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import 'dto/chat_request.dart';
import 'dto/chat_response.dart';

/// DeepSeek API 抽象（对照 Kotlin DeepSeekApi.kt 的 Retrofit 接口）。
abstract class DeepSeekApi {
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request, {
    CancelToken? cancelToken,
  });
}

/// dio 实现：POST v1/chat/completions，Bearer 鉴权。
/// 对照 Kotlin NetworkModule.kt：JSON ignoreUnknownKeys/isLenient 语义
/// 由响应 DTO 宽容解析（未知键忽略、缺省字段用默认值）承担。
class DioDeepSeekApi implements DeepSeekApi {
  DioDeepSeekApi(this._dio, {this.baseUrl = AppConfig.deepSeekBaseUrl}) {
    if (_dio.options.baseUrl.isEmpty) {
      _dio.options.baseUrl = baseUrl;
    }
  }

  final Dio _dio;
  final String baseUrl;

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post<Map<String, Object?>>(
      'v1/chat/completions',
      data: request.toJson(),
      cancelToken: cancelToken,
      options: Options(headers: {
        'Authorization': 'Bearer ${AppConfig.deepSeekApiKey}',
        'Content-Type': 'application/json',
      }),
    );
    return ChatCompletionResponse.fromJson(response.data!);
  }
}
