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

/// 等待状态机走到 [status]（401 → authCallback 的 handleServerFailure 异步
/// 清 token + 置态，drift I/O 需真实事件循环；不阻塞首屏的启动校验用例用）。
Future<void> _waitForStatus(AuthService service, AuthStatus status) async {
  for (var i = 0; i < 100; i++) {
    if (service.state.status == status) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

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
  /// 注入的机型名（fake DeviceLabelReader；null = 读不到 → body 不含 device_name）。
  String? deviceLabel;

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
      readDeviceLabel: () async => deviceLabel,
    );
    line1Number = null;
    deviceLabel = null;
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

    test('2. token 有效（未过期）→ 不调登录接口 → 立即 loggedIn', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-valid',
        expiresAtMillis: now + 3600000,
      );
      // 登录接口一旦被调即失败：有效 token 不允许静默重登；
      // 启动校验的 /api/auth/me 正常应答（异步、不阻塞首屏）
      adapter.handler = (options) async => options.uri.path == '/api/auth/login'
          ? throw StateError('有效 token 不应调用登录接口: ${options.uri}')
          : _json(200, {'code': 0, 'data': {}});

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
        // 预览（守卫）不计入：只统计真正的登录请求，验证单飞
        if (options.uri.path == '/api/auth/login') loginCalls++;
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

    test('token 过期 + preview 网络失败 → 不重登（fail-closed → loggedOut）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok-stale',
        expiresAtMillis: now - 1000,
      );
      line1Number = '13800000000';
      var loginCalled = false;
      adapter.handler = (options) async {
        if (options.uri.path == '/api/auth/login') loginCalled = true;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      };

      await service.ensureLoggedIn(); // 不抛

      expect(loginCalled, isFalse); // 预览失败 → 不自动登录（转手动）
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

      final outcome = await service.loginWithPhone('13912345678');

      expect(outcome.result, AuthResult.success);
      expect(outcome.evicted, isEmpty);
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

      final outcome = await service.loginWithPhone('13912345678');

      expect(outcome.result, AuthResult.banned);
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

      final outcome = await service.loginWithPhone('13912345678');

      expect(outcome.result, AuthResult.networkError);
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

  group('登录预览与静默重登守卫', () {
    test('checkLoginImpact：有将被挤设备 → willEvict', () async {
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {
              'evicted': [
                {'device_id': 'old1', 'device_name': 'Xiaomi 14', 'issued_at': 1758000000000}
              ]
            }
          });
      final impact = await service.checkLoginImpact('13800000000');
      expect(impact.kind, LoginImpactKind.willEvict);
      expect(impact.evicted.single.deviceId, 'old1');
      expect(adapter.lastRequest!.uri.path, '/api/auth/login/preview');
    });

    test('checkLoginImpact：网络失败 → networkError（不登录）', () async {
      adapter.handler = (_) async => throw DioException(
          requestOptions: RequestOptions(path: '/api/auth/login/preview'),
          type: DioExceptionType.connectionError);
      expect((await service.checkLoginImpact('13800000000')).kind,
          LoginImpactKind.networkError);
    });

    test('静默重登：会挤人 → 不登录（loggedOut）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(db, phone: '13800000000', token: 'tok-stale', expiresAtMillis: now - 1000);
      line1Number = '13800000000';
      var loginCalled = false;
      adapter.handler = (options) async {
        if (options.uri.path == '/api/auth/login/preview') {
          return _json(200, {
            'code': 0,
            'data': {
              'evicted': [
                {'device_id': 'other', 'device_name': 'iPad', 'issued_at': 1758000000000}
              ]
            }
          });
        }
        loginCalled = true;
        return _json(200, {'code': 0, 'data': {'token': 'x', 'expires_at': 9999999999}});
      };

      await service.ensureLoggedIn();

      expect(loginCalled, isFalse);
      expect(service.state.status, AuthStatus.loggedOut);
    });

    test('静默重登：不挤人 → 正常登录（带 device_name）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(db, phone: '13800000000', token: 'tok-stale', expiresAtMillis: now - 1000);
      line1Number = '13800000000';
      deviceLabel = 'Xiaomi 14';
      adapter.handler = (options) async => options.uri.path == '/api/auth/login/preview'
          ? _json(200, {'code': 0, 'data': {'evicted': []}})
          : _json(200, {'code': 0, 'data': {'token': 'tok-new', 'expires_at': 9999999999}});

      await service.ensureLoggedIn();

      expect(service.state.status, AuthStatus.loggedIn);
      expect(adapter.lastRequest!.uri.path, '/api/auth/login');
      expect(adapter.lastRequest!.data, {
        'phone': '13800000000',
        'device_id': deviceId,
        'device_name': 'Xiaomi 14',
      });
    });
  });

  group('被踢通知与启动校验', () {
    test('handleServerFailure(evicted, detail) → 通知 + 清 token；consume 后只弹一次', () async {
      await _seedAuth(db, phone: '13800000000', token: 'tok', expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 1000);
      await service.handleServerFailure(AuthFailureKind.evicted, {
        'reason': 'evicted',
        'ended_at': 1758000000123,
        'by': {'device_id': 'd3', 'device_name': 'iPhone 15 Pro', 'issued_at': 1758000000000},
      });

      expect(service.state.status, AuthStatus.evicted);
      final notice = service.state.evictionNotice!;
      expect(notice.reason, EvictionReason.evicted);
      expect(notice.by!.deviceName, 'iPhone 15 Pro');
      expect(notice.endedAtMillis, 1758000000123);
      expect((await dao.get())!.serverToken, isNull); // token 已清

      service.consumeEvictionNotice();
      expect(service.state.evictionNotice, isNull);
      expect(service.state.status, AuthStatus.loggedOut);
    });

    test('待展示通知期间 401 TOKEN_EXPIRED → loggedOut 但通知保留（不得吞掉）', () async {
      // 通知已生成、还挂在屏幕上（未点「知道了」）
      await service.handleServerFailure(AuthFailureKind.evicted, {
        'reason': 'evicted',
        'ended_at': 1758000000123,
        'by': {'device_id': 'd3', 'device_name': 'iPhone 15 Pro', 'issued_at': 1758000000000},
      });
      expect(service.state.evictionNotice, isNotNull);

      // 此间任何携带空 token 的受保护请求返回 401 TOKEN_EXPIRED
      // （token 已被上一步清空）→ 状态归位 loggedOut，但通知必须原样保留
      await service.handleServerFailure(AuthFailureKind.tokenExpired, null);

      expect(service.state.status, AuthStatus.loggedOut);
      expect(service.state.evictionNotice, isNotNull);
      expect(service.state.evictionNotice!.by!.deviceName, 'iPhone 15 Pro');
      expect(service.state.evictionNotice!.endedAtMillis, 1758000000123);
    });

    test('clearKickedStatus 保留通知（守卫清状态不吞提示）', () async {
      await service.handleServerFailure(AuthFailureKind.evicted, null);
      service.clearKickedStatus();
      expect(service.state.status, AuthStatus.loggedOut);
      expect(service.state.evictionNotice, isNotNull); // 无 detail → 通用通知
      expect(service.state.evictionNotice!.by, isNull); // 不编造下手设备
    });

    test('detail.reason=relogin → 通知原因 relogin（同设备重登挤掉旧会话）', () async {
      await service.handleServerFailure(AuthFailureKind.evicted, {
        'reason': 'relogin',
        'ended_at': 1758000000999,
        'by': {'device_id': 'd9', 'device_name': 'iPhone 15 Pro', 'issued_at': 1758000000000},
      });

      final notice = service.state.evictionNotice!;
      expect(notice.reason, EvictionReason.relogin);
      expect(notice.by!.deviceId, 'd9');
      expect(notice.endedAtMillis, 1758000000999);
    });

    test('detail.by 畸形（形状对但缺字段）→ 不抛，回退通用通知 + token 已清', () async {
      await _seedAuth(
        db,
        phone: '13800000000',
        token: 'tok',
        expiresAtMillis: DateTime.now().millisecondsSinceEpoch + 3600000,
      );

      // by 非空对象但缺 device_id / issued_at（脏数据 / 老服务端）：
      // SessionDevice.fromJson 会抛 TypeError —— 401 回调 fire-and-forget，
      // 抛出即「token 已清但状态未置」的残局，必须回退通用通知
      await service.handleServerFailure(AuthFailureKind.evicted, {
        'reason': 'evicted',
        'ended_at': 1758000000123,
        'by': <String, dynamic>{},
      });

      expect(service.state.status, AuthStatus.evicted);
      expect(service.state.evictionNotice, isNotNull);
      expect(service.state.evictionNotice!.by, isNull); // 通用通知，不编造设备
      expect((await dao.get())!.serverToken, isNull);   // token 已清
    });

    test('启动校验：本地 token 有效但服务端已踢 → evicted + 通知', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(db, phone: '13800000000', token: 'tok-valid', expiresAtMillis: now + 3600000);
      // 生产由 providers 接线；单测里显式接上（401 经此回调收尾）
      client.setAuthCallback(service.handleServerFailure);
      adapter.handler = (options) async => options.uri.path == '/api/auth/me'
          ? _json(401, {
              'code': 401,
              'message': 'unauthorized',
              'error_code': 'EVICTED',
              'detail': {
                'reason': 'evicted',
                'ended_at': 1758000000123,
                'by': {'device_id': 'd9', 'device_name': 'iPad', 'issued_at': 1758000000000},
              }
            })
          : throw StateError('不应调用其他接口: ${options.uri}');

      await service.ensureLoggedIn();
      expect(service.state.status, AuthStatus.loggedIn); // 首屏不等网络
      await service.inflightSessionValidation;           // 等校验完成
      await _waitForStatus(service, AuthStatus.evicted); // 401 回调异步收尾

      expect(service.state.status, AuthStatus.evicted);
      expect(service.state.evictionNotice!.by!.deviceName, 'iPad');
      expect((await dao.get())!.serverToken, isNull);
    });

    test('启动校验：网络失败 → 保持 loggedIn（不误报）', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _seedAuth(db, phone: '13800000000', token: 'tok-valid', expiresAtMillis: now + 3600000);
      adapter.handler = (_) async => throw DioException(
          requestOptions: RequestOptions(path: '/api/auth/me'),
          type: DioExceptionType.connectionError);

      await service.ensureLoggedIn();
      await service.inflightSessionValidation;

      expect(service.state.status, AuthStatus.loggedIn);
      expect(service.state.evictionNotice, isNull);
    });
  });
}
