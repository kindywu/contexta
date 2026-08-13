import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repository/settings_repository.dart';
import '../remote/auth_api.dart';
import '../remote/server_api_client.dart';

/// 登录状态机取值。
enum AuthStatus {
  /// 尚未初始化（首次构建，需要 ensureLoggedIn 探测本地 token）。
  unknown,

  /// 未登录（无 token / token 已清理 / 静默重登失败）。
  loggedOut,

  /// 已登录（本地 token 有效或登录成功）。
  loggedIn,

  /// 被服务端踢下线（EVICTED：token 被吊销，需重新登录）。
  evicted,

  /// 被封禁（BANNED：不可再登录）。
  banned,
}

/// 登录态（UI 消费：路由守卫 / 登录页 / 首页提示条）。
class AuthState {
  const AuthState({required this.status, this.phone, this.tokenExpiresAt});

  final AuthStatus status;

  /// 已登录 / 曾登录的手机号。
  final String? phone;

  /// token 过期时间（Unix 毫秒，与 user_settings.server_token_expires_at 一致）。
  final int? tokenExpiresAt;

  @override
  String toString() =>
      'AuthState(status=$status, phone=$phone, tokenExpiresAt=$tokenExpiresAt)';
}

/// loginWithPhone 的返回类别（登录页据此展示文案；不抛异常）。
enum AuthResult {
  success,

  /// 服务端 BANNED（403）。
  banned,

  /// 网络不可用（连接失败 / 超时）。
  networkError,

  /// 其他服务端 / 协议错误。
  serverError,
}

/// 登录状态机（riverpod StateNotifier）。
///
/// 职责：
/// - [ensureLoggedIn]：启动 / 守卫恢复——本地 token 未过期直接 loggedIn；
///   过期且有本机号码 → 静默重登（失败不抛）；否则 loggedOut。
/// - [loginWithPhone]：免密登录（本机号码或手动输入），成功落库 + loggedIn。
/// - [logout]：调 /api/auth/logout + 清 token（接口失败也继续本地登出）。
/// - [handleServerFailure]：ServerApiClient 401 回调（tokenExpired → loggedOut；
///   evicted / banned → 对应状态），均清 token。
///
/// 依赖注入（测试替换）：SettingsRepository（drift 内存库 / fake）、
/// ServerApiClient（mock dio）、deviceId / readPhone 回调（fake）。
class AuthService extends StateNotifier<AuthState> {
  AuthService({
    required ServerApiClient api,
    required SettingsRepository settings,
    required Future<String> Function() deviceId,
    required Future<String?> Function() readPhone,
  })  : _api = AuthApi(api),
        _settings = settings,
        _deviceId = deviceId,
        _readPhone = readPhone,
        super(const AuthState(status: AuthStatus.unknown));

  /// 认证 API（内部包一层 [ServerApiClient]：URL / 解包 / 秒转毫秒）。
  final AuthApi _api;
  final SettingsRepository _settings;
  final Future<String> Function() _deviceId;
  final Future<String?> Function() _readPhone;

  /// 当前状态（StateNotifier 的 state 仅限子类访问，外部经此读取）。
  AuthState get authState => state;

  /// 当前状态机取值（路由守卫等外部读取快捷方式）。
  AuthStatus get status => state.status;

  /// 启动 / 401 恢复：token 有效直接 loggedIn；过期且可读号码 → 静默重登；
  /// 否则 loggedOut（静默失败不抛）。
  Future<void> ensureLoggedIn() async {
    final settings = await _settings.getSettings();
    final token = settings?.serverToken;
    final expiresAt = settings?.serverTokenExpiresAt;
    final phone = settings?.serverPhone;
    if (token == null || expiresAt == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.loggedOut);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (expiresAt > now) {
      state = AuthState(
        status: AuthStatus.loggedIn,
        phone: phone,
        tokenExpiresAt: expiresAt,
      );
      return;
    }
    // token 过期：本机号码可读 → 静默重登（免密登录语义，按当前 SIM 卡号码
    // 重新登录）；读不到 / 失败一律 loggedOut（静默，不抛）
    final nativePhone = await _readPhone();
    if (nativePhone == null || nativePhone.isEmpty) {
      state = const AuthState(status: AuthStatus.loggedOut);
      return;
    }
    final result = await loginWithPhone(nativePhone);
    if (result != AuthResult.success) {
      state = const AuthState(status: AuthStatus.loggedOut);
    }
  }

  /// 免密登录（本机号码 / 手动输入）。成功写 user_settings 并置 loggedIn；
  /// 失败返回 [AuthResult]（不抛异常）。
  Future<AuthResult> loginWithPhone(String phone) async {
    final deviceId = await _deviceId();
    try {
      final login = await _api.login(phone: phone, deviceId: deviceId);
      await _settings.saveAuth(
        phone: phone,
        token: login.token,
        tokenExpiresAtMillis: login.expiresAtMillis,
      );
      state = AuthState(
        status: AuthStatus.loggedIn,
        phone: phone,
        tokenExpiresAt: login.expiresAtMillis,
      );
      return AuthResult.success;
    } on ServerApiException catch (e) {
      if (e.errorCode == 'BANNED') return AuthResult.banned;
      if (e.errorCode == 'NETWORK') return AuthResult.networkError;
      return AuthResult.serverError;
    } catch (_) {
      return AuthResult.serverError;
    }
  }

  /// 登出：调 /api/auth/logout（失败不抛）+ 清本地 token。
  Future<void> logout() async {
    try {
      final deviceId = await _deviceId();
      await _api.logout(deviceId: deviceId);
    } catch (_) {
      // 登出接口失败也继续本地登出
    }
    await _settings.clearAuth();
    state = const AuthState(status: AuthStatus.loggedOut);
  }

  /// ServerApiClient 401 回调：清 token + 按类别置状态。
  Future<void> handleServerFailure(AuthFailureKind kind) async {
    await _settings.clearAuth();
    switch (kind) {
      case AuthFailureKind.tokenExpired:
        state = const AuthState(status: AuthStatus.loggedOut);
      case AuthFailureKind.evicted:
        state = const AuthState(status: AuthStatus.evicted);
      case AuthFailureKind.banned:
        state = const AuthState(status: AuthStatus.banned);
    }
  }
}
