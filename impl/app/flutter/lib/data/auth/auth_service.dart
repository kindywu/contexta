import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repository/settings_repository.dart';
import '../remote/auth_api.dart';
import '../remote/dto/session_device_dto.dart';
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

/// 被踢通知原因：evicted = 被其他设备挤掉；relogin = 本机重新登录（旧 token 失效）。
enum EvictionReason { evicted, relogin }

/// 被踢通知（UI 一次性弹窗消费；无服务端 detail 时为通用通知）。
class EvictionNotice {
  const EvictionNotice({
    required this.reason,
    required this.endedAtMillis,
    this.by,
  });

  final EvictionReason reason;
  final int endedAtMillis;

  /// 下手设备（无 detail 时为 null → 通用文案）。
  final SessionDevice? by;
}

/// 登录态（UI 消费：路由守卫 / 登录页 / 首页提示条）。
class AuthState {
  const AuthState({
    required this.status,
    this.phone,
    this.tokenExpiresAt,
    this.evictionNotice,
  });

  final AuthStatus status;

  /// 已登录 / 曾登录的手机号。
  final String? phone;

  /// token 过期时间（Unix 毫秒，与 user_settings.server_token_expires_at 一致）。
  final int? tokenExpiresAt;

  /// 待展示的被踢通知（UI 消费后经 [AuthService.consumeEvictionNotice] 清空）。
  final EvictionNotice? evictionNotice;

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

/// 登录影响预览结果类别。
enum LoginImpactKind { clear, willEvict, networkError, serverError }

/// 登录影响预览结果（[evicted] 仅在 willEvict 时有值）。
class LoginImpact {
  const LoginImpact(this.kind, [this.evicted = const []]);

  final LoginImpactKind kind;
  final List<SessionDevice> evicted;
}

/// loginWithPhone 的完整结果（result + 实际被挤设备，供并发差异提示）。
class LoginOutcome {
  const LoginOutcome({required this.result, this.evicted = const []});

  final AuthResult result;
  final List<SessionDevice> evicted;
}

/// 登录状态机（riverpod StateNotifier）。
///
/// 职责：
/// - [ensureLoggedIn]：启动 / 守卫恢复——本地 token 未过期直接 loggedIn
///   （并异步做一次服务端校验，不阻塞首屏）；过期且 preview 不挤人 → 静默重登；
///   会挤人 / 网络失败 / 读不到号码 → loggedOut（转手动登录）。
/// - [checkLoginImpact]：登录前预览（会挤人 → UI 需确认；错误一律 fail-closed）。
/// - [loginWithPhone]：免密登录（本机号码或手动输入），成功落库 + loggedIn，
///   返回 [LoginOutcome]（含本次实际被挤设备）。
/// - [logout]：调 /api/auth/logout + 清 token（接口失败也继续本地登出）。
/// - [handleServerFailure]：ServerApiClient 401 回调（tokenExpired → loggedOut；
///   evicted → evicted + 一次性通知；banned → banned），均清 token。
/// - [clearKickedStatus] / [consumeEvictionNotice]：被踢状态与通知的收尾
///   （守卫清状态保留通知；UI 消费通知后清空）。
///
/// 依赖注入（测试替换）：SettingsRepository（drift 内存库 / fake）、
/// ServerApiClient（mock dio）、deviceId / readPhone / readDeviceLabel 回调（fake）。
class AuthService extends StateNotifier<AuthState> {
  AuthService({
    required ServerApiClient api,
    required this._settings,
    required this._deviceId,
    required this._readPhone,
    required this._readDeviceLabel,
  })  : _api = AuthApi(api),
        super(const AuthState(status: AuthStatus.unknown));

  /// 认证 API（内部包一层 [ServerApiClient]：URL / 解包 / 秒转毫秒）。
  final AuthApi _api;
  final SettingsRepository _settings;
  final Future<String> Function() _deviceId;
  final Future<String?> Function() _readPhone;

  /// 设备机型名读取（登录上报 device_name；不可用 → null）。
  final Future<String?> Function() _readDeviceLabel;

  /// 当前状态（StateNotifier 的 state 仅限子类访问，外部经此读取）。
  AuthState get authState => state;

  /// 当前状态机取值（路由守卫等外部读取快捷方式）。
  AuthStatus get status => state.status;

  /// 启动 / 401 恢复：token 有效直接 loggedIn；过期且可读号码 → 静默重登；
  /// 否则 loggedOut（静默失败不抛）。
  ///
  /// 单飞保护：并发调用（守卫 + 页面同时触发）复用同一 in-flight Future，
  /// 避免双调 login API 双写 token。
  Future<void> ensureLoggedIn() {
    final inFlight = _inflightEnsure;
    if (inFlight != null) return inFlight;
    final future = _doEnsureLoggedIn();
    _inflightEnsure = future;
    return future.whenComplete(() {
      if (identical(_inflightEnsure, future)) _inflightEnsure = null;
    });
  }

  /// 进行中的 ensureLoggedIn（单飞：进行中复用，完成后置空）。
  Future<void>? _inflightEnsure;

  /// 启动校验的进行中 Future（测试等待用；不阻塞首屏）。
  @visibleForTesting
  Future<void>? inflightSessionValidation;

  Future<void> _doEnsureLoggedIn() async {
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
      // 启动校验：异步、不阻塞首屏；401 由 ServerApiClient 的 authCallback 收尾
      inflightSessionValidation = _validateSession();
      return;
    }
    // token 过期：本机号码可读 → 静默重登；但会挤人 / 网络失败一律不自动登（转手动）
    final nativePhone = await _readPhone();
    if (nativePhone == null || nativePhone.isEmpty) {
      state = const AuthState(status: AuthStatus.loggedOut);
      return;
    }
    final impact = await checkLoginImpact(nativePhone);
    if (impact.kind != LoginImpactKind.clear) {
      state = const AuthState(status: AuthStatus.loggedOut);
      return;
    }
    final outcome = await loginWithPhone(nativePhone);
    if (outcome.result != AuthResult.success) {
      state = const AuthState(status: AuthStatus.loggedOut);
    }
  }

  /// 本地 token 有效时的服务端校验：被踢 → authCallback 清 token + 置通知；
  /// 网络失败 → 保持本地登录态（离线不误报）。
  Future<void> _validateSession() async {
    try {
      await _api.me();
    } catch (_) {
      // 网络失败 / 401：后者已由 handleServerFailure 处理，此处不重复
    }
  }

  /// 登录影响预览：会挤人（willEvict）/ 不挤人（clear）/ 网络或服务端错误。
  /// 错误一律 fail-closed —— 调用方不得在非 clear 时继续登录。
  Future<LoginImpact> checkLoginImpact(String phone) async {
    final deviceId = await _deviceId();
    try {
      final preview = await _api.previewLogin(phone: phone, deviceId: deviceId);
      return preview.evicted.isEmpty
          ? const LoginImpact(LoginImpactKind.clear)
          : LoginImpact(LoginImpactKind.willEvict, preview.evicted);
    } on ServerApiException catch (e) {
      return LoginImpact(
        e.errorCode == 'NETWORK'
            ? LoginImpactKind.networkError
            : LoginImpactKind.serverError,
      );
    } catch (_) {
      return const LoginImpact(LoginImpactKind.serverError);
    }
  }

  /// 被踢 / 封禁后的收尾：状态清为 loggedOut（token 已在 handleServerFailure
  /// 清除）。路由守卫遇到 evicted/banned 时调用——本地浏览不受影响，
  /// 仅消除「被踢」残留态；幂等（非 kicked 状态无操作）。
  ///
  /// **保留**待展示通知：守卫只清状态，不吞被踢提示（由 UI 消费后清）。
  void clearKickedStatus() {
    if (state.status == AuthStatus.evicted || state.status == AuthStatus.banned) {
      state = AuthState(
        status: AuthStatus.loggedOut,
        phone: state.phone,
        tokenExpiresAt: state.tokenExpiresAt,
        evictionNotice: state.evictionNotice,
      );
    }
  }

  /// UI 展示完被踢通知后调用（幂等）。evicted 残留态一并归位 loggedOut
  /// （守卫下次导航也会清，但弹窗可能是最后一次状态变更，这里直接收口）。
  void consumeEvictionNotice() {
    if (state.evictionNotice == null) return;
    state = AuthState(
      status: state.status == AuthStatus.evicted
          ? AuthStatus.loggedOut
          : state.status,
      phone: state.phone,
      tokenExpiresAt: state.tokenExpiresAt,
    );
  }

  /// 免密登录（本机号码 / 手动输入）。成功写 user_settings 并置 loggedIn；
  /// 失败返回 [LoginOutcome]（不抛异常）。
  Future<LoginOutcome> loginWithPhone(String phone) async {
    final deviceId = await _deviceId();
    final deviceLabel = await _readDeviceLabel();
    try {
      final login = await _api.login(
        phone: phone,
        deviceId: deviceId,
        deviceName: deviceLabel,
      );
      debugPrint(
          '[AuthService] login OK, saving auth token=${login.token.length > 16 ? '${login.token.substring(0, 16)}...' : login.token}');
      await _settings.saveAuth(
        phone: phone,
        token: login.token,
        tokenExpiresAtMillis: login.expiresAtMillis,
      );
      debugPrint('[AuthService] saveAuth done, state→loggedIn');
      state = AuthState(
        status: AuthStatus.loggedIn,
        phone: phone,
        tokenExpiresAt: login.expiresAtMillis,
      );
      return LoginOutcome(result: AuthResult.success, evicted: login.evicted);
    } on ServerApiException catch (e) {
      debugPrint('[AuthService] login failed: code=${e.errorCode} msg=${e.message}');
      if (e.errorCode == 'BANNED') {
        return const LoginOutcome(result: AuthResult.banned);
      }
      if (e.errorCode == 'NETWORK') {
        return const LoginOutcome(result: AuthResult.networkError);
      }
      return const LoginOutcome(result: AuthResult.serverError);
    } catch (e, st) {
      debugPrint('[AuthService] login UNEXPECTED: $e\n$st');
      return const LoginOutcome(result: AuthResult.serverError);
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

  /// ServerApiClient 401 回调：清 token + 按类别置状态；EVICTED 组装一次性通知。
  /// [detail]：服务端 error body 的 detail（仅 EVICTED 携带「谁 / 何时挤掉本机」），
  /// 缺失 / 畸形 → 通用通知（不编造设备）。
  Future<void> handleServerFailure(
    AuthFailureKind kind, [
    Map<String, dynamic>? detail,
  ]) async {
    debugPrint('[AuthService] handleServerFailure: kind=$kind — CLEARING TOKEN');
    await _settings.clearAuth();
    switch (kind) {
      case AuthFailureKind.tokenExpired:
        state = const AuthState(status: AuthStatus.loggedOut);
      case AuthFailureKind.evicted:
        state = AuthState(
          status: AuthStatus.evicted,
          evictionNotice: _noticeFromDetail(detail),
        );
      case AuthFailureKind.banned:
        state = const AuthState(status: AuthStatus.banned);
    }
  }

  /// 解析服务端 detail（缺失/畸形 → 通用通知，不编造设备）。
  EvictionNotice _noticeFromDetail(Map<String, dynamic>? detail) {
    final endedAt = detail?['ended_at'];
    final by = detail?['by'];
    final reason = detail?['reason'] == 'relogin'
        ? EvictionReason.relogin
        : EvictionReason.evicted;
    if (endedAt is! num || by is! Map<String, dynamic>) {
      return EvictionNotice(
        reason: reason,
        endedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return EvictionNotice(
      reason: reason,
      endedAtMillis: endedAt.toInt(),
      by: SessionDevice.fromJson(by),
    );
  }
}
