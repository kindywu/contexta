import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/data/auth/auth_service.dart';
import 'package:contexta/data/remote/dto/session_device_dto.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/ui/auth/eviction_notice_host.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 被踢提示测试：
/// - EvictionNoticePanel（纯展示）：有 by / 无 by 通用文案 / relogin 三态；
/// - EvictionNoticeHost（接线）：消费后不再弹、relogin 跳登录页、本地模式透传。
void main() {
  testWidgets('展示「设备 + 时间」文案', (tester) async {
    final notice = EvictionNotice(
      reason: EvictionReason.evicted,
      endedAtMillis: DateTime(2026, 9, 18, 14, 32).millisecondsSinceEpoch,
      by: const SessionDevice(
        deviceId: 'abcdef123456',
        deviceName: 'Xiaomi 14',
        issuedAtMillis: 1758000000000,
      ),
    );
    var dismissed = false;
    var relogin = false;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        EvictionNoticePanel(
          notice: notice,
          onDismiss: () => dismissed = true,
          onRelogin: () => relogin = true,
        ),
      ]),
    ));

    expect(find.text('账号已在其他设备登录'), findsOneWidget);
    expect(find.textContaining('Xiaomi 14 · 3456'), findsOneWidget);
    expect(find.textContaining('09-18 14:32'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    expect(dismissed, isTrue);
    await tester.tap(find.text('重新登录'));
    expect(relogin, isTrue);
  });

  testWidgets('无 detail → 通用文案（不编造设备）', (tester) async {
    final notice = EvictionNotice(
      reason: EvictionReason.evicted,
      endedAtMillis: DateTime(2026, 9, 18, 14, 32).millisecondsSinceEpoch,
    );
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        EvictionNoticePanel(notice: notice, onDismiss: () {}, onRelogin: () {}),
      ]),
    ));
    expect(find.textContaining('登录状态已失效，请重新登录'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('relogin → 本机重新登录文案', (tester) async {
    final notice = EvictionNotice(
      reason: EvictionReason.relogin,
      endedAtMillis: DateTime(2026, 9, 18, 14, 32).millisecondsSinceEpoch,
      by: const SessionDevice(deviceId: 'self0001', deviceName: 'iPad', issuedAtMillis: 0),
    );
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        EvictionNoticePanel(notice: notice, onDismiss: () {}, onRelogin: () {}),
      ]),
    ));
    expect(find.text('本机已重新登录'), findsOneWidget);
  });

  group('EvictionNoticeHost 接线', () {
    late _FakeSettingsRepo settings;
    late AuthService service;

    setUp(() {
      settings = _FakeSettingsRepo();
      service = AuthService(
        api: ServerApiClient(
          Dio(),
          baseUrl: 'https://api.example.com',
          tokenProvider: () async => null,
        ),
        settings: settings,
        deviceId: () async => 'dev-1',
        readPhone: () async => null,
        readDeviceLabel: () async => null,
      );
    });

    Future<void> pumpHost(
      WidgetTester tester, {
      bool serverConfigured = true,
    }) async {
      final router = GoRouter(
        initialLocation: Routes.home,
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (_, _) => const Scaffold(body: Text('home-page')),
          ),
          GoRoute(
            path: Routes.login,
            builder: (_, _) => const Scaffold(body: Text('login-page')),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          serverConfiguredProvider.overrideWithValue(serverConfigured),
          authServiceProvider.overrideWith((ref) => service),
          routerProvider.overrideWithValue(router),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              EvictionNoticeHost(child: child ?? const SizedBox.shrink()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('通知出现 → 弹窗；点「知道了」→ 消费后不再弹', (tester) async {
      await service.handleServerFailure(AuthFailureKind.evicted, {
        'reason': 'evicted',
        'ended_at': DateTime(2026, 9, 18, 14, 32).millisecondsSinceEpoch,
        'by': {
          'device_id': 'abcdef123456',
          'device_name': 'Xiaomi 14',
          'issued_at': 1758000000000,
        },
      });
      await pumpHost(tester);

      expect(find.text('账号已在其他设备登录'), findsOneWidget);
      expect(find.textContaining('Xiaomi 14 · 3456'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      expect(find.text('账号已在其他设备登录'), findsNothing);
      expect(service.state.evictionNotice, isNull);
    });

    testWidgets('relogin → 「重新登录」跳登录页（宿主在 Router 之上，走 routerProvider）',
        (tester) async {
      await service.handleServerFailure(AuthFailureKind.evicted, {
        'reason': 'relogin',
        'ended_at': DateTime(2026, 9, 18, 14, 32).millisecondsSinceEpoch,
        'by': {
          'device_id': 'self0001',
          'device_name': 'iPad',
          'issued_at': 1758000000000,
        },
      });
      await pumpHost(tester);

      expect(find.text('本机已重新登录'), findsOneWidget);
      await tester.tap(find.text('重新登录'));
      await tester.pumpAndSettle();

      expect(find.text('login-page'), findsOneWidget);
      expect(service.state.evictionNotice, isNull);
    });

    testWidgets('本地模式（serverConfigured=false）→ 有通知也透传不弹', (tester) async {
      await service.handleServerFailure(AuthFailureKind.evicted, null);
      await pumpHost(tester, serverConfigured: false);

      expect(find.text('账号已在其他设备登录'), findsNothing);
      expect(find.text('登录状态已失效，请重新登录。'), findsNothing);
      expect(find.text('home-page'), findsOneWidget);
    });
  });
}

/// 设置仓储桩（不动真实库）：AuthService 只需 clearAuth/getSettings。
class _FakeSettingsRepo implements SettingsRepository {
  UserSettings settings = const UserSettings();

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  Future<void> clearAuth() async {
    settings = const UserSettings();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}
