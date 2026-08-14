import '../../domain/model/word_detail.dart';
import 'dto/word_lookup_dto.dart';
import 'server_api_client.dart';

/// 服务端 LLM 网关 API（查词远程化）。
///
/// 走 [ServerApiClient]（envelope 解包 + 认证拦截 + 错误映射）；
/// 服务端错误抛 [ServerApiException]，调用点经 [mapErrorCodeToException]
/// 映射为既有异常分类（LlmFatal / LlmRecoverableExhausted / LlmTimeout /
/// PipelineBlocking / QuotaExceeded）——阅读页「仅词头」/ 加词页错误提示
/// 的降级语义保持不变。
class LlmApi {
  LlmApi(this._client);

  final ServerApiClient _client;

  /// 查词：POST /api/llm/word-lookup {word} → [WordDetail]。
  ///
  /// 服务端保证返回 ≥ 1 个义项；data 非对象 / 义项为空视为解析失败
  /// （前者 [ServerApiException] UNKNOWN，后者 [FormatException]），
  /// 均由调用点既有降级路径处理，不让 TypeError 裸逃逸。
  Future<WordDetail> wordLookup(String word) async {
    final dto = await _client.post<WordLookupDto>(
      '/api/llm/word-lookup',
      body: {'word': word},
      parser: (data) {
        if (data is! Map<String, dynamic>) {
          throw ServerApiException(
            errorCode: 'UNKNOWN',
            message: 'word-lookup 接口 data 不是 JSON 对象'
                '（实际 ${data.runtimeType}）',
          );
        }
        return WordLookupDto.fromJson(data);
      },
    );
    return dto.toWordDetail();
  }
}
