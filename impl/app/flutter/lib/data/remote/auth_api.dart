import 'dto/session_device_dto.dart';
import 'server_api_client.dart';

/// 登录接口返回值（[expiresAtMillis] 已从服务端秒转为毫秒，对齐
/// user_settings.server_token_expires_at 的 Unix 毫秒）。
class AuthLoginResult {
  const AuthLoginResult({
    required this.token,
    required this.expiresAtMillis,
    this.evicted = const [],
  });

  final String token;
  final int expiresAtMillis;

  /// 本次登录实际挤下线的设备（并发下可能与预览不同；空 = 没挤人）。
  final List<SessionDevice> evicted;
}

/// 登录预览返回值：此刻登录将被挤掉的设备（0/1 条）。
class LoginPreviewResult {
  const LoginPreviewResult({required this.evicted});

  final List<SessionDevice> evicted;
}

List<SessionDevice> _parseEvicted(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(SessionDevice.fromJson)
      .toList();
}

/// 认证 API（服务端契约，字段名精确）：
/// - `POST /api/auth/login` body `{phone, device_id, device_name?, code?}` →
///   `{code:0, data:{token, expires_at, evicted:[...]}}`（expires_at 单位：秒，
///   evicted 时间单位：毫秒）；
/// - `POST /api/auth/login/preview` body `{phone, device_id}` →
///   `{code:0, data:{evicted:[...]}}`（不落库）；
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
    String? deviceName,
    String? code,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/api/auth/login',
      body: {
        'phone': phone,
        'device_id': deviceId,
        'device_name': ?deviceName,
        'code': ?code,
      },
    );
    final token = data['token'] as String;
    final expiresAtSec = (data['expires_at'] as num).toInt(); // 秒
    return AuthLoginResult(
      token: token,
      expiresAtMillis: expiresAtSec * 1000,
      evicted: _parseEvicted(data['evicted']),
    );
  }

  /// 登录预览（不落库）：此刻登录会挤掉谁。
  Future<LoginPreviewResult> previewLogin({
    required String phone,
    required String deviceId,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/api/auth/login/preview',
      body: {'phone': phone, 'device_id': deviceId},
    );
    return LoginPreviewResult(evicted: _parseEvicted(data['evicted']));
  }

  Future<void> logout({required String deviceId}) =>
      _client.post<void>('/api/auth/logout', body: {'device_id': deviceId},
          parser: (_) {});

  Future<Map<String, dynamic>?> me() => _client.get<Map<String, dynamic>>(
        '/api/auth/me',
        parser: (data) => data as Map<String, dynamic>,
      );
}
