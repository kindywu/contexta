import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/core/navigation/app_router.dart';
import 'package:contexta/core/navigation/routes.dart';
import 'package:contexta/data/auth/auth_service.dart';
import 'package:contexta/data/auth/native_phone_reader.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/remote/llm_api.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/ui/auth/login_screen.dart';
import 'package:contexta/ui/home/home_screen.dart';
import 'package:contexta/ui/reading/reading_screen.dart';
import 'package:contexta/ui/settings/settings_screen.dart';
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

class _FakeLlmApi implements LlmApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// TTS 桩：reading/settings 页会 watch ttsEngineProvider，真实工厂
/// （kittentts 模型安装）在测试环境残留 Timer。
class _TtsStub implements TtsEngine {
  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) => 'id';

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnParagraphStarted(
    void Function(String? utteranceId, int paragraphIndex, int total)?
        callback,
  ) {}
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
        llmApiProvider.overrideWithValue(_FakeLlmApi()),
        // reading/settings 页会 watch TTS：真实工厂在测试环境残留 Timer
        ttsEngineProvider.overrideWith((ref) async => _TtsStub()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  List<String> stackLocations() => router.routerDelegate.currentConfiguration
      .matches
      .map((m) => m.matchedLocation)
      .toList();

  group('登录守卫（本地浏览豁免）', () {
    testWidgets('未登录访问 /home → 放行，横幅「未登录」+ 登录入口可见',
        (tester) async {
      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
      // 未登录横幅（服务端已配置）可访问：登录页由横幅/按钮驱动
      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('未登录访问 /reading/:id → 放行（本地阅读可用）', (tester) async {
      await pumpApp(tester);
      router.go(Routes.readingRoute(7));
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/reading/7']);
      expect(find.byType(ReadingScreen), findsOneWidget);
    });

    testWidgets('横幅 → 登录页 → 快速登录成功 → 回 home', (tester) async {
      line1 = '13800000000';
      adapter.handler = (options) async => _json(200, {
            'code': 0,
            'data': {'token': 'tok-1', 'expires_at': 9999999999},
          });

      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();

      // 首页横幅 → 登录页
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // 快速登录成功 → 守卫回跳 home
      await tester.tap(find.text('本机号码快速登录'));
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(service.state.status, AuthStatus.loggedIn);
    });

    testWidgets('登录页「暂不登录，先逛逛」→ 回 home（不再被弹回）',
        (tester) async {
      await pumpApp(tester);
      router.go(Routes.home);
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.text('暂不登录，先逛逛'));
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(service.state.status, AuthStatus.loggedOut);
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
      expect(find.text('未登录'), findsNothing);
    });

    testWidgets('被踢（evicted）→ 清为 loggedOut，留在当前页不跳登录',
        (tester) async {
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

      // 不强制重定向：本地浏览不受影响；状态清为 loggedOut + 横幅出现
      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(service.state.status, AuthStatus.loggedOut);
      expect(settings.settings.serverToken, isNull);
      expect(find.text('未登录'), findsOneWidget);
    });
  });

  group('已登录访问登录页（from 校验）', () {
    setUp(() {
      // 已登录态：有效 token
      settings.settings = UserSettings(
        serverPhone: '13800000000',
        serverToken: 'tok-valid',
        serverTokenExpiresAt:
            DateTime.now().millisecondsSinceEpoch + 3600000,
      );
    });

    testWidgets('/login?from=/login → 忽略 from 回 home（防重定向循环）',
        (tester) async {
      await pumpApp(tester);
      router.go('${Routes.login}?from=/login');
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('/login?from=/settings → 回跳 settings', (tester) async {
      await pumpApp(tester);
      router.go('${Routes.login}?from=${Uri.encodeComponent(Routes.settings)}');
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/settings']);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('/login 无 from → 回 home', (tester) async {
      await pumpApp(tester);
      router.go(Routes.login);
      await tester.pumpAndSettle();

      expect(stackLocations(), ['/home']);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
