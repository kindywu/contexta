import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/core/components/app_button.dart';
import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/data/auth/auth_service.dart';
import 'package:contexta/data/auth/native_phone_reader.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/ui/auth/login_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 登录页测试：快速登录（本机号码）→ 自动登录；读不到号码 → 手动输入；
/// 错误 SnackBar（BANNED / 网络失败）；服务端未配置提示。
///
/// 注入：真实 AuthService + mock dio（stub adapter）+ fake 号码读取。
/// 路由守卫不在本测试范围（登录成功后的回跳在 app_router 集成测试）。
class _StubAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options) handler = _unset;

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

class _FakePhoneReader implements NativePhoneReader {
  _FakePhoneReader(this.phone, {this.supportsLine1Number = true});
  String? phone;

  /// 默认 true（Android 语义）——iOS 场景（false）由专门用例构造。
  @override
  final bool supportsLine1Number;

  @override
  Future<String?> readLine1Number() async => phone;
}

class _FakeSettingsRepo implements SettingsRepository {
  UserSettings settings = const UserSettings();

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  Future<void> saveAuth({
    required String phone,
    required String token,
    required int tokenExpiresAtMillis,
  }) async {
    settings = UserSettings(
      serverPhone: phone,
      serverToken: token,
      serverTokenExpiresAt: tokenExpiresAtMillis,
    );
  }

  @override
  Future<void> clearAuth() async {
    settings = const UserSettings();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

void main() {
  late _StubAdapter adapter;
  late _FakeSettingsRepo settings;
  late AuthService service;
  String? line1;

  setUp(() {
    adapter = _StubAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ServerApiClient(
      dio,
      baseUrl: 'https://api.example.com',
      tokenProvider: () async => null,
    );
    settings = _FakeSettingsRepo();
    service = AuthService(
      api: client,
      settings: settings,
      deviceId: () async => 'dev-1',
      readPhone: () async => line1,
      readDeviceLabel: () async => null,
    );
    line1 = null;
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        serverConfiguredProvider.overrideWithValue(true),
        nativePhoneReaderProvider.overrideWithValue(_FakePhoneReader(line1)),
        authServiceProvider.overrideWith((ref) => service),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: Routes.login,
          routes: [
            GoRoute(
              path: Routes.login,
              builder: (context, state) => const LoginScreen(),
            ),
            // 登录成功回跳目标（登录页不手动导航，此路由仅承接 go(home)）
            GoRoute(
              path: Routes.home,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('home'))),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('登录页渲染', () {
    testWidgets('AppBar 登录 + 快速登录主按钮，初始无手动输入框', (tester) async {
      line1 = '13800000000';
      await pumpLogin(tester);

      expect(find.text('登录'), findsOneWidget);
      expect(find.text('本机号码快速登录'), findsOneWidget);
      expect(find.text('手机号'), findsNothing);
      expect(find.text('暂不登录，先逛逛'), findsOneWidget);
    });

    testWidgets('服务端未配置 → 配置提示 + 按钮禁用', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          serverConfiguredProvider.overrideWithValue(false),
          nativePhoneReaderProvider.overrideWithValue(_FakePhoneReader(null)),
          authServiceProvider.overrideWith((ref) => service),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('服务端未配置，当前为本地模式'), findsOneWidget);
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.enabled, isFalse);
    });

    testWidgets('平台不支持读本机号码（iOS）→ 无快速登录按钮，直接手动输入',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          serverConfiguredProvider.overrideWithValue(true),
          nativePhoneReaderProvider.overrideWithValue(
            _FakePhoneReader(null, supportsLine1Number: false),
          ),
          authServiceProvider.overrideWith((ref) => service),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ));
      await tester.pumpAndSettle();

      // 没有「本机号码快速登录」，手动输入框与登录按钮直接可见
      expect(find.text('本机号码快速登录'), findsNothing);
      expect(find.text('手机号'), findsOneWidget);
      expect(find.text('登录'), findsNWidgets(2)); // AppBar 标题 + 主按钮
    });
  });

  group('本机号码快速登录', () {
    testWidgets('读到号码 → 自动调 /api/auth/login（phone + device_id）',
        (tester) async {
      line1 = '13800000000';
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'token': 'tok-1', 'expires_at': 9999999999},
          });

      await pumpLogin(tester);
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(adapter.lastRequest!.uri.path, '/api/auth/login');
      expect(adapter.lastRequest!.data,
          {'phone': '13800000000', 'device_id': 'dev-1'});
      // 成功 → 无错误 SnackBar，登录态写入，回跳 home
      expect(find.byType(SnackBar), findsNothing);
      expect(service.state.status, AuthStatus.loggedIn);
      expect(settings.settings.serverToken, 'tok-1');
      expect(settings.settings.serverTokenExpiresAt, 9999999999 * 1000);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('读不到号码 → 展开手动输入框（不调接口）', (tester) async {
      line1 = null;
      // 触发接口即失败：读不到号码不允许自动登录
      adapter.handler = (options) async =>
          throw StateError('读不到号码不应调接口: ${options.uri}');

      await pumpLogin(tester);
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(find.text('手机号'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '登录'), findsOneWidget);
      expect(adapter.lastRequest, isNull);
    });

    testWidgets('BANNED → SnackBar 封禁文案，状态不变更', (tester) async {
      line1 = '13800000000';
      // 预览放行：本用例测的是 login 返回 BANNED 的展示；若预览也 403，
      // fail-closed 会在预览阶段拦截（且文案是「登录失败」），测不到本路径。
      adapter.handler = (options) async {
        if (options.uri.path == '/api/auth/login/preview') {
          return _json(200, {'code': 0, 'data': {'evicted': []}});
        }
        return _json(403, {
          'code': 403,
          'message': 'banned',
          'error_code': 'BANNED',
        });
      };

      await pumpLogin(tester);
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(find.text('账号已被封禁，无法登录'), findsOneWidget);
      expect(service.state.status, isNot(AuthStatus.loggedIn));
    });

    testWidgets('网络失败 → SnackBar 网络文案', (tester) async {
      line1 = '13800000000';
      adapter.handler = (options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      };

      await pumpLogin(tester);
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(find.text('网络不可用，请检查网络后重试'), findsOneWidget);
    });
  });

  group('手动输入登录', () {
    testWidgets('输入 11 位手机号 → 登录成功', (tester) async {
      line1 = null;
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'token': 'tok-2', 'expires_at': 7777777777},
          });

      await pumpLogin(tester);
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '13912345678');
      await tester.tap(find.widgetWithText(AppButton, '登录'));
      await tester.pumpAndSettle();

      expect(adapter.lastRequest!.data,
          {'phone': '13912345678', 'device_id': 'dev-1'});
      expect(service.state.status, AuthStatus.loggedIn);
      expect(service.state.phone, '13912345678');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('非法手机号 → 提示且不调接口', (tester) async {
      line1 = null;
      adapter.handler = (options) async =>
          throw StateError('非法号码不应调接口');

      await pumpLogin(tester);
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.widgetWithText(AppButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SnackBar, '请输入 11 位手机号'), findsOneWidget);
      expect(adapter.lastRequest, isNull);
    });
  });

  group('登录预览确认框', () {
    Future<ResponseBody> previewThenLogin(
        RequestOptions options, List<String> paths) async {
      paths.add(options.uri.path);
      if (options.uri.path == '/api/auth/login/preview') {
        return _json(200, {
          'code': 0,
          'data': {
            'evicted': [
              {'device_id': 'old1', 'device_name': 'Xiaomi 14', 'issued_at': 1758000000000}
            ]
          }
        });
      }
      return _json(200, {'code': 0, 'data': {'token': 'tok-1', 'expires_at': 9999999999}});
    }

    testWidgets('预览会挤人 → 弹确认框；取消 → 不登录不挤人', (tester) async {
      final paths = <String>[];
      adapter.handler = (options) => previewThenLogin(options, paths);
      line1 = '13800000000';
      await pumpLogin(tester);

      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(find.text('将有一台设备退出登录'), findsOneWidget);
      expect(find.textContaining('Xiaomi 14 · old1'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('将有一台设备退出登录'), findsNothing);
      expect(paths.where((p) => p == '/api/auth/login'), isEmpty); // 未登录
      expect(settings.settings.serverToken, isNull);
      expect(find.text('本机号码快速登录'), findsOneWidget); // loading 已复位
    });

    testWidgets('确认「继续登录」→ 调 login 并成功回跳', (tester) async {
      final paths = <String>[];
      adapter.handler = (options) => previewThenLogin(options, paths);
      line1 = '13800000000';
      await pumpLogin(tester);

      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续登录'));
      await tester.pumpAndSettle();

      expect(paths, contains('/api/auth/login'));
      expect(settings.settings.serverToken, 'tok-1');
      expect(find.text('home'), findsOneWidget); // 登录成功回跳
      expect(find.byType(SnackBar), findsNothing); // 实际挤人 = 预览 → 不提示差异
    });

    testWidgets('预览为空 → 不弹框直接登录', (tester) async {
      final paths = <String>[];
      adapter.handler = (options) async {
        paths.add(options.uri.path);
        if (options.uri.path == '/api/auth/login/preview') {
          return _json(200, {'code': 0, 'data': {'evicted': []}});
        }
        return _json(200, {'code': 0, 'data': {'token': 'tok-2', 'expires_at': 9999999999}});
      };
      line1 = '13800000000';
      await pumpLogin(tester);

      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(find.text('将有一台设备退出登录'), findsNothing);
      expect(paths, contains('/api/auth/login/preview')); // 确实走了预览
      expect(paths, contains('/api/auth/login'));
    });

    testWidgets('预览服务端错误（fail-closed）→ 不登录、有提示、loading 复位',
        (tester) async {
      final paths = <String>[];
      adapter.handler = (options) async {
        paths.add(options.uri.path);
        return _json(500, {
          'code': 500,
          'message': 'boom',
          'error_code': 'INTERNAL',
        });
      };
      line1 = '13800000000';
      await pumpLogin(tester);

      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(find.text('登录失败，请稍后重试'), findsOneWidget);
      expect(paths, isNot(contains('/api/auth/login'))); // 预览失败不登录
      expect(settings.settings.serverToken, isNull);
      expect(find.text('本机号码快速登录'), findsOneWidget); // loading 已复位
    });

    testWidgets('并发差异：实际挤掉的与预览不同 → 登录成功并提示实际设备',
        (tester) async {
      final paths = <String>[];
      adapter.handler = (options) async {
        paths.add(options.uri.path);
        if (options.uri.path == '/api/auth/login/preview') {
          return _json(200, {
            'code': 0,
            'data': {
              'evicted': [
                {'device_id': 'old1', 'device_name': 'Xiaomi 14', 'issued_at': 1758000000000}
              ]
            }
          });
        }
        // 预览说 old1，实际挤掉的是 old2（并发下另一台先登录）
        return _json(200, {
          'code': 0,
          'data': {
            'token': 'tok-1',
            'expires_at': 9999999999,
            'evicted': [
              {'device_id': 'old2', 'device_name': 'iPad', 'issued_at': 1758000000000}
            ]
          }
        });
      };
      line1 = '13800000000';
      await pumpLogin(tester);

      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续登录'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SnackBar, '已将《iPad · old2》挤下线'), findsOneWidget);
      expect(find.text('home'), findsOneWidget); // 差异不阻断登录
    });
  });
}
