import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/core/navigation/app_router.dart';
import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/data/auth/auth_service.dart';
import 'package:contexta/data/auth/native_phone_reader.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/domain/model/generation_error.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/domain/llm_client.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/ui/auth/login_screen.dart';
import 'package:contexta/ui/home/home_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 登录守卫集成测试：守卫重定向（未登录 → /login?from=…）、登录成功回跳
/// （refreshListenable 自动重估）、已登录放行、被踢（evicted）→ /login。
///
/// 服务端「已配置」经 serverConfiguredProvider override 模拟（测试环境
/// SERVER_BASE_URL 为空 = 本地模式，不启用守卫）。
class _StubAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options) handler = _unset;

  static Future<ResponseBody> _unset(RequestOptions _) =>
      throw StateError('stub adapter: handler 未设置');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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
  _FakePhoneReader(this.phone);
  String? phone;

  @override
  Future<String?> readLine1Number() async => phone;
}

class _FakeSettingsRepo implements SettingsRepository {
  UserSettings settings = const UserSettings();

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Future<bool> isOnboarded() async => settings.isOnboarded;

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

class _FakeArticleRepo implements ArticleRepository {
  @override
  Future<bool> isPipelineBlocked() async => false;

  @override
  Stream<List<GenerationError>> observeGenerationErrors() =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStatsRepo implements StatsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeVocabRepo implements VocabularyRepository {
  @override
  Future<List<VocabWord>> getActiveWords() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeWordRepo implements WordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeLlmClient implements LlmClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

void main() {
  late _StubAdapter adapter;
  late _FakeSettingsRepo settings;
  late AuthService service;
  late GoRouter router;
  String? line1;

  setUp(() {
    adapter = _StubAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ServerApiClient(
      dio,
      baseUrl: 'https://api.example.com',
      tokenProvider: () async => settings.settings.serverToken,
    );
    settings = _FakeSettingsRepo();
    service = AuthService(
      api: client,
      settings: settings,
      deviceId: () async => 'dev-1',
      readPhone: () async => line1,
    );
    router = buildRouter(authService: service);
    line1 = null;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // Onboarding 页会读 databaseProvider：用内存库避免真实数据库打开
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        serverConfiguredProvider.overrideWithValue(true),
        nativePhoneReaderProvider.overrideWithValue(_FakePhoneReader(line1)),
        authServiceProvider.overrideWith((ref) => service),
        articleRepositoryProvider.overrideWithValue(_FakeArticleRepo()),
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
        statsRepositoryProvider.overrideWithValue(_FakeStatsRepo()),
        vocabularyRepositoryProvider.overrideWithValue(_FakeVocabRepo()),
        wordRepositoryProvider.overrideWithValue(_FakeWordRepo()),
        llmClientProvider.overrideWithValue(_FakeLlmClient()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  List<String> stackLocations() => router.routerDelegate.currentConfiguration
      .matches
      .map((m) => m.matchedLocation)
      .toList();

  group('登录守卫', () {
    testWidgets('未登录访问 /home → 重定向 /login（带 from 回跳参数）',
        (tester) async {
      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/login']);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('登录成功 → 自动回跳来源页（from=/home → /home）',
        (tester) async {
      line1 = '13800000000';
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'token': 'tok-1', 'expires_at': 9999999999},
          });

      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(service.state.status, AuthStatus.loggedIn);
    });

    testWidgets('本地 token 有效 → 放行（不回登录页）', (tester) async {
      settings.settings = UserSettings(
        serverPhone: '13800000000',
        serverToken: 'tok-valid',
        serverTokenExpiresAt:
            DateTime.now().millisecondsSinceEpoch + 3600000,
      );

      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('被踢（evicted）→ 自动重定向 /login', (tester) async {
      settings.settings = UserSettings(
        serverPhone: '13800000000',
        serverToken: 'tok-x',
        serverTokenExpiresAt: DateTime.now().millisecondsSinceEpoch + 3600000,
      );

      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      await service.handleServerFailure(AuthFailureKind.evicted);
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/login']);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
