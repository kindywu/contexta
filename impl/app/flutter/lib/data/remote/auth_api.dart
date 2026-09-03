import 'server_api_client.dart';

/// 登录接口返回值（[expiresAtMillis] 已从服务端秒转为毫秒，对齐
/// user_settings.server_token_expires_at 的 Unix 毫秒）。
class AuthLoginResult {
  const AuthLoginResult({required this.token, required this.expiresAtMillis});

  final String token;
  final int expiresAtMillis;
}

/// 认证 API（服务端契约，字段名精确）：
/// - `POST /api/auth/login` body `{phone, device_id, code?}` →
///   `{code:0, data:{token, expires_at}}`（expires_at 单位：秒）；
/// - `POST /api/auth/logout` body `{device_id}`；
/// - `GET /api/auth/me`。
///
/// 错误经 [ServerApiClient] 统一转 [ServerApiException]（含认证类 401 回调）。
class AuthApi {
  AuthApi(this._client);

  final ServerApiClient _client;

  Future<AuthLoginResult> login({
    required String phone,
    required String deviceId,
    String? code,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/api/auth/login',
      body: {
        'phone': phone,
        'device_id': deviceId,
        'code': ?code,
      },
    );
    final token = data['token'] as String;
    final expiresAtSec = (data['expires_at'] as num).toInt(); // 秒
    return AuthLoginResult(
      token: token,
      expiresAtMillis: expiresAtSec * 1000,
    );
  }

  Future<void> logout({required String deviceId}) =>
      _client.post<void>('/api/auth/logout', body: {'device_id': deviceId},
          parser: (_) {});

  Future<Map<String, dynamic>?> me() => _client.get<Map<String, dynamic>>(
        '/api/auth/me',
        parser: (data) => data as Map<String, dynamic>,
      );
}
