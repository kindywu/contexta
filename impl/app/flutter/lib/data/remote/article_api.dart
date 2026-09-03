import 'dto/article_dto.dart';
import 'server_api_client.dart';

/// 服务端文章 API。
///
/// 走 [ServerApiClient]（envelope 解包 + 认证拦截 + 错误映射），
/// 契约字段精确见 dto/article_dto.dart。
class ArticleApi {
  ArticleApi(this._client);

  final ServerApiClient _client;

  /// 拉取本次投放（服务端按难度游标/配额/同日冻结计算；difficulty 为
  /// App 当前难度设置，count 为每日篇数设置——服务端负责截断到配额）。
  ///
  /// data 非 Map（防御，与 ServerApiClient 的畸形响应防御一致）→
  /// 抛 [ServerApiException]（UNKNOWN）。
  Future<ArticleDeliveryDto> fetchDelivery({
    required String difficulty,
    required int count,
  }) => _client.get(
    '/api/articles/delivery',
    query: {'difficulty': difficulty, 'count': count},
    parser: (data) {
      if (data is! Map) {
        throw ServerApiException(
          errorCode: 'UNKNOWN',
          message: '投放接口 data 不是对象（实际 ${data.runtimeType}）',
        );
      }
      return ArticleDeliveryDto.fromJson(data.cast<String, dynamic>());
    },
  );
}
