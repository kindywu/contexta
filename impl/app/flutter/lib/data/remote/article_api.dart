import 'dto/article_dto.dart';
import 'server_api_client.dart';

/// 服务端文章 API。
///
/// 走 [ServerApiClient]（envelope 解包 + 认证拦截 + 错误映射），
/// 契约字段精确见 dto/article_dto.dart。
class ArticleApi {
  ArticleApi(this._client);

  final ServerApiClient _client;

  /// 拉取今日已审核文章（服务端已按难度 / 顺序排好）。
  ///
  /// data 非数组（防御，与 ServerApiClient 的畸形响应防御一致）→
  /// 抛 [ServerApiException]（UNKNOWN），不让 TypeError 裸逃逸。
  Future<List<ArticleDto>> fetchTodayArticles() => _client.get(
    '/api/articles/today',
    parser: (data) {
      if (data is! List) {
        throw ServerApiException(
          errorCode: 'UNKNOWN',
          message: '今日文章接口 data 不是数组（实际 ${data.runtimeType}）',
        );
      }
      return [
        for (final e in data)
          ArticleDto.fromJson((e as Map).cast<String, dynamic>()),
      ];
    },
  );
}
