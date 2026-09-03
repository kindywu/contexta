class AppConfig {
  /// 服务端 API origin（无尾斜杠，如 https://api.example.com）；
  /// ServerApiClient 以 `$serverBaseUrl$path` 拼接请求 URL。
  static const serverBaseUrl = String.fromEnvironment('SERVER_BASE_URL');
}
