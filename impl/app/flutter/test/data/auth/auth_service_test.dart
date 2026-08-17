import 'dart:convert';

import 'package:contexta/data/auth/auth_service.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/settings_daos.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/data/repository/settings_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// AuthService 测试：状态机（unknown/loggedOut/loggedIn/evicted/banned）与
/// token 生命周期（ensureLoggedIn / loginWithPhone / logout / handleServerFailure）。
///
/// 注入：SettingsRepository（drift 内存库——验证 token 真落库）、
/// ServerApiClient（自定义 HttpClientAdapter，不触网）、DeviceId（fake）、
/// NativePhoneReader（fake）。
class _StubAdapter implements HttpClientAdapter {
  /// (options) -> 响应体；抛异常模拟网络错误。
  Future<ResponseBody> Function(RequestOptions options) handler = _unset;

  /// 最近一次进入适配器的请求（断言 URL / 方法 / body）。
  RequestOptions? lastRequest;

  static Future<ResponseBody> _unset(RequestOptions _) =>
      throw StateError('stub adapter: handler 未设置');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int statusCode, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );

/// 预置 user_settings 单行（登录态 3 列可空）。
Future<void> _seedAuth(
  AppDatabase db, {
  String? phone,
  String? token,
  int? expiresAtMillis,
}) =>
    UserSettingsDao(db).upsert(UserSettingsCompanion(
      id: const Value(1),
      isOnboarded: const Value(false),
      difficultyLevel: const Value('MEDIUM'),
      dailyArticleCount: const Value(3),
      translationDisplayMode: const Value('FULL'),
      ttsSpeed: const Value(1.0),
      ttsVoiceId: const Value('BELLA'),
      masteryThresholdN: const Value(1),
      autoPlayAudio: const Value(false),
      serverPhone: Value(phone),
      serverToken: Value(token),
      serverTokenExpiresAt: Value(expiresAtMillis),
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late UserSettingsDao dao;
  late SettingsRepositoryImpl settings;
  late _StubAdapter adapter;
  late ServerApiClient client;
  late AuthService service;

  /// 注入的 deviceId（fake DeviceIdProvider）。
  String deviceId = 'dev-fixed-001';
  /// 注入的本机号码（fake NativePhoneReader；null = 读不到）。
  String? line1Number;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = UserSettingsDao(db);
    settings = SettingsRepositoryImpl(dao);
    adapter = _StubAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    client = ServerApiClient(
      dio,
      baseUrl: 'https://api.example.com',
      tokenProvider: () async => null,
    );
    service = AuthService(
      api: client,
      settings: settings,
      deviceId: () async => deviceId,
      readPhone: () async => line1Number,
    );
    line1Number = null;
  });

  tearDown(() async {
    await db.close();
  });

  group('ensureLoggedIn（启动/401 恢复）', () {
    test('1. 无 token 且无本机号码 → loggedOut（静默失败不抛）', () async {
      // 库为空（无 user_settings 行）→ 无 token
      await service.ensureLoggedIn();

      expect(service.state.status, AuthStatus.loggedOut);
      expect(service.state.phone, isNull);
    });

    test('2. token 有效（未过期）→ 不调 API → loggedIn', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-valid',
        expiresAtMillis: now + 3600000,
      );
      // 一旦触网即失败：有效 token 不允许调登录接口
      adapter.handler = (options) async =>
          throw StateError('有效 token 不应调用任何 API: ${options.uri}');

      await service.ensureLoggedIn();

      expect(service.state.status, AuthStatus.loggedIn);
      expect(service.state.phone, '13800000000');
      expect(service.state.tokenExpiresAt, now + 3600000);
    });

    test('3. token 过期 + 本机号码存在 → 调 login 成功 → loggedIn + token 落库',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-stale',
        expiresAtMillis: now - 1000, // 已过期
      );
      line1Number = '13800000000';
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {
              'token': 'tok-fresh',
              'expires_at': 9999999999, // 秒（服务端契约）
            },
          });

      await service.ensureLoggedIn();

      expect(service.state.status, AuthStatus.loggedIn);
      // 请求体：phone + device_id（本机号码 → 免密登录）
      expect(adapter.lastRequest!.uri.path, '/api/auth/login');
      expect(adapter.lastRequest!.data,
          {'phone': '13800000000', 'device_id': deviceId});
      // token 落库（expires_at 秒 → 毫秒）
      final row = await dao.get();
      expect(row!.serverToken, 'tok-fresh');
      expect(row.serverTokenExpiresAt, 9999999999 * 1000);
      expect(row.serverPhone, '13800000000');
    });

    test('并发两次 ensureLoggedIn → login API 只调 1 次（单飞）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-stale',
        expiresAtMillis: now - 1000,
      );
      line1Number = '13800000000';
      var loginCalls = 0;
      adapter.handler = (options) async {
        loginCalls++;
        return _json(200, {
          'code': 0,
          'data': {'token': 'tok-fresh', 'expires_at': 9999999999},
        });
      };

      await Future.wait([service.ensureLoggedIn(), service.ensureLoggedIn()]);

      expect(loginCalls, 1); // 双调 login 会双写 token
      expect(service.state.status, AuthStatus.loggedIn);
      final row = await dao.get();
      expect(row!.serverToken, 'tok-fresh');
    });

    test('token 过期但本机号码读不到 → loggedOut（静默失败不抛）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-stale',
        expiresAtMillis: now - 1000,
      );
      line1Number = null; // 读不到号码

      await service.ensureLoggedIn();

      expect(service.state.status, AuthStatus.loggedOut);
    });

    test('token 过期 + 本机号码存在但登录接口失败 → loggedOut（静默）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-stale',
        expiresAtMillis: now - 1000,
      );
      line1Number = '13800000000';
      adapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      };

      await service.ensureLoggedIn(); // 不抛

      expect(service.state.status, AuthStatus.loggedOut);
    });
  });

  group('loginWithPhone', () {
    test('4. 成功 → user_settings 写入 server_phone/server_token/expires_at',
        () async {
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {
              'token': 'tok-1',
              'expires_at': 8888888888,
            },
          });

      final result = await service.loginWithPhone('13912345678');

      expect(result, AuthResult.success);
      expect(adapter.lastRequest!.uri.path, '/api/auth/login');
      expect(adapter.lastRequest!.data,
          {'phone': '13912345678', 'device_id': deviceId});
      final row = await dao.get();
      expect(row!.serverPhone, '13912345678');
      expect(row.serverToken, 'tok-1');
      expect(row.serverTokenExpiresAt, 8888888888 * 1000);
      expect(service.state.status, AuthStatus.loggedIn);
      expect(service.state.phone, '13912345678');
    });

    test('BANNED（403）→ AuthResult.banned，状态不变更', () async {
      adapter.handler = (options) async => _json(403, {
            'code': 403,
            'message': 'banned',
            'error_code': 'BANNED',
          });

      final result = await service.loginWithPhone('13912345678');

      expect(result, AuthResult.banned);
      expect(service.state.status, isNot(AuthStatus.loggedIn));
    });

    test('网络错误 → AuthResult.networkError', () async {
      adapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      };

      final result = await service.loginWithPhone('13912345678');

      expect(result, AuthResult.networkError);
    });
  });

  group('handleServerFailure（401 回调接线）', () {
    test('5. evicted → status=evicted + 清 token', () async {
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-x',
        expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 3600000,
      );

      await service.handleServerFailure(AuthFailureKind.evicted);

      expect(service.state.status, AuthStatus.evicted);
      final row = await dao.get();
      expect(row!.serverToken, isNull);
      expect(row.serverTokenExpiresAt, isNull);
    });

    test('banned → status=banned + 清 token', () async {
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-x',
        expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 3600000,
      );

      await service.handleServerFailure(AuthFailureKind.banned);

      expect(service.state.status, AuthStatus.banned);
      final row = await dao.get();
      expect(row!.serverToken, isNull);
    });

    test('tokenExpired → status=loggedOut + 清 token', () async {
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-x',
        expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 3600000,
      );

      await service.handleServerFailure(AuthFailureKind.tokenExpired);

      expect(service.state.status, AuthStatus.loggedOut);
      final row = await dao.get();
      expect(row!.serverToken, isNull);
    });
  });

  group('logout', () {
    test('6. 调 /api/auth/logout + 清 token + loggedOut', () async {
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-x',
        expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 3600000,
      );
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': null,
          });

      await service.logout();

      expect(adapter.lastRequest!.uri.path, '/api/auth/logout');
      expect(adapter.lastRequest!.data, {'device_id': deviceId});
      expect(service.state.status, AuthStatus.loggedOut);
      final row = await dao.get();
      expect(row!.serverToken, isNull);
      expect(row.serverPhone, isNull);
    });

    test('登出接口失败也继续本地登出（不抛）', () async {
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-x',
        expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 3600000,
      );
      adapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      };

      await service.logout(); // 不抛

      expect(service.state.status, AuthStatus.loggedOut);
      final row = await dao.get();
      expect(row!.serverToken, isNull);
    });
  });
}
