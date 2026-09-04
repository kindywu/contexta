import 'dart:convert';
import 'dart:typed_data';

import 'package:contexta/core/components/app_modal.dart';
import 'package:contexta/data/auth/auth_service.dart';
import 'package:contexta/data/remote/server_api_client.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/daily_stats.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/settings/settings_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings 页 widget 测试（Task 26）。
/// 逻辑已由 settings_controller_test 覆盖（17 个），此处验证 UI 接线：
/// - tabs 切换（学习设置 / 学习统计 + 统计卡片）
/// - 设置项渲染（picker 值 / stepper / 开关）
/// - 弹窗流：选择器 → 确认修改；ℹ️ → 信息弹窗；取消
/// - 路由接线（app_router_test 覆盖）

/// 退出登录测试用：dio stub 适配器（不触网），记录最近请求供断言。
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

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo();

  UserSettings settings = const UserSettings(isOnboarded: true);
  final List<String> updates = [];

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Future<void> updateLevel(String level) async {
    updates.add('level:$level');
    settings = UserSettings(
      isOnboarded: settings.isOnboarded,
      difficultyLevel: level,
      dailyArticleCount: settings.dailyArticleCount,
      translationDisplayMode: settings.translationDisplayMode,
      masteryThresholdN: settings.masteryThresholdN,
      autoPlayAudio: settings.autoPlayAudio,
    );
  }

  @override
  Future<bool> updateDailyArticleCount(int newCount) async {
    updates.add('count:$newCount');
    settings = UserSettings(
      isOnboarded: settings.isOnboarded,
      difficultyLevel: settings.difficultyLevel,
      dailyArticleCount: newCount,
      translationDisplayMode: settings.translationDisplayMode,
      masteryThresholdN: settings.masteryThresholdN,
      autoPlayAudio: settings.autoPlayAudio,
    );
    return true;
  }

  @override
  Future<void> updateTtsSpeed(double speed) async {
    updates.add('ttsSpeed:$speed');
  }

  @override
  Future<void> updateTranslationMode(String mode) async {
    updates.add('mode:$mode');
    settings = UserSettings(
      isOnboarded: settings.isOnboarded,
      difficultyLevel: settings.difficultyLevel,
      dailyArticleCount: settings.dailyArticleCount,
      translationDisplayMode: mode,
      masteryThresholdN: settings.masteryThresholdN,
      autoPlayAudio: settings.autoPlayAudio,
    );
  }

  @override
  Future<void> updateMasteryThreshold(int n) async {
    updates.add('threshold:$n');
    settings = UserSettings(
      isOnboarded: settings.isOnboarded,
      difficultyLevel: settings.difficultyLevel,
      dailyArticleCount: settings.dailyArticleCount,
      translationDisplayMode: settings.translationDisplayMode,
      masteryThresholdN: n,
      autoPlayAudio: settings.autoPlayAudio,
    );
  }

  @override
  Future<void> updateAutoPlayAudio(bool enabled) async {
    updates.add('autoPlay:$enabled');
    settings = UserSettings(
      isOnboarded: settings.isOnboarded,
      difficultyLevel: settings.difficultyLevel,
      dailyArticleCount: settings.dailyArticleCount,
      translationDisplayMode: settings.translationDisplayMode,
      masteryThresholdN: settings.masteryThresholdN,
      autoPlayAudio: enabled,
    );
  }

  @override
  Future<void> updateTtsVoice(TtsVoice voice) async {
    updates.add('voice:${voice.dbValue}');
    settings = UserSettings(
      isOnboarded: settings.isOnboarded,
      difficultyLevel: settings.difficultyLevel,
      dailyArticleCount: settings.dailyArticleCount,
      translationDisplayMode: settings.translationDisplayMode,
      ttsVoice: voice,
      masteryThresholdN: settings.masteryThresholdN,
      autoPlayAudio: settings.autoPlayAudio,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStatsRepo implements StatsRepository {
  _FakeStatsRepo({this.stats});

  final DailyStats? stats;

  @override
  Future<DailyStats?> getStats() async => stats;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// TTS 引擎桩：记录 speak 调用（文本 + 音色）与 stop 调用供试听断言。
class _TtsStub implements TtsEngine {
  final List<String> spoken = [];
  final List<TtsVoice?> spokenVoices = [];
  int stopCount = 0;

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    spoken.add(text);
    spokenVoices.add(voice);
    return 'ctx-1';
  }

  @override
  void stop() {
    stopCount++;
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnParagraphStarted(
      void Function(String? utteranceId, int paragraphIndex, int total)?
          callback) {}
}

const _stats = DailyStats(
  totalArticlesRead: 12,
  totalWordsAdded: 34,
  totalWordsMastered: 5,
  totalLearningDays: 6,
  currentStreak: 3,
  longestStreak: 7,
  lastActiveDate: '2026-08-08',
);

void main() {
  late _FakeSettingsRepo settingsRepo;
  late _FakeStatsRepo statsRepo;
  late _TtsStub tts;
  late _StubAdapter adapter;
  late AuthService authService;

  setUp(() {
    settingsRepo = _FakeSettingsRepo();
    statsRepo = _FakeStatsRepo(stats: _stats);
    tts = _TtsStub();
    adapter = _StubAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ServerApiClient(
      dio,
      baseUrl: 'https://api.example.com',
      tokenProvider: () async => null,
    );
    authService = AuthService(
      api: client,
      settings: settingsRepo,
      deviceId: () async => 'dev-1',
      readPhone: () async => null,
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        statsRepositoryProvider.overrideWithValue(statsRepo),
        ttsEngineProvider.overrideWith((ref) async => tts),
        authServiceProvider.overrideWith((ref) => authService),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// 预置已登录状态（stub 登录接口成功，AuthService → loggedIn）。
  /// 注：必须在 runAsync（真实 async zone）中 await——testWidgets 的
  /// FakeAsync 环境直接 await 请求链会挂起（login_screen_test 先例：
  /// 请求由 tap + pumpAndSettle 驱动；此处无 UI 可点，故用 runAsync）。
  Future<void> seedLoggedIn(WidgetTester tester, String phone) async {
    adapter.handler = (options) async => _json(200, {
          'code': 0,
          'data': {'token': 'tok-1', 'expires_at': 9999999999},
        });
    await tester.runAsync(() => authService.loginWithPhone(phone));
    expect(authService.status, AuthStatus.loggedIn);
  }

  group('tabs 切换', () {
    testWidgets('默认学习设置 tab；切到学习统计显示 2×2 卡片', (tester) async {
      await pumpScreen(tester);

      expect(find.text('学习设置'), findsOneWidget);
      expect(find.text('英文水平'), findsOneWidget);

      await tester.tap(find.text('学习统计'));
      await tester.pumpAndSettle();

      expect(find.text('12'), findsOneWidget); // 阅读文章
      expect(find.text('34'), findsOneWidget); // 添加单词
      expect(find.text('6'), findsOneWidget); // 累计学习天数
      expect(find.text('3'), findsOneWidget); // 当前连续学习
      expect(find.text('英文水平'), findsNothing);
    });
  });

  group('设置项渲染', () {
    testWidgets('picker 值显示当前设置（中级 / 完全显示）', (tester) async {
      await pumpScreen(tester);

      expect(find.text('中级'), findsOneWidget);
      expect(find.text('完全显示'), findsOneWidget);
    });

    testWidgets('stepper 显示当前值（3 / 1）', (tester) async {
      await pumpScreen(tester);

      expect(find.text('3'), findsOneWidget); // 每日文章数量
      expect(find.text('1'), findsOneWidget); // 掌握阈值
    });

    testWidgets('自动朗读开关初始 off，点击后 on', (tester) async {
      await pumpScreen(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(settingsRepo.updates, contains('autoPlay:true'));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });

  group('难度修改弹窗流', () {
    testWidgets('点击英文水平 → 选择器 → 选择高级 → 确认弹窗 → 确认修改',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('中级'));
      await tester.pumpAndSettle();
      expect(find.text('选择英文水平'), findsOneWidget);

      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();
      expect(find.text('修改英文水平'), findsOneWidget);
      expect(find.text('此设置将在明天生效，今天的学习不受影响。'), findsOneWidget);

      await tester.tap(find.text('确认修改'));
      await tester.pumpAndSettle();

      expect(settingsRepo.updates, contains('level:HIGH'));
      expect(find.text('修改英文水平'), findsNothing);
      expect(find.text('高级'), findsOneWidget); // picker 值已更新
    });

    testWidgets('确认弹窗点取消 → 不生效', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('中级'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(settingsRepo.updates, isEmpty);
      expect(find.text('中级'), findsOneWidget);
    });
  });

  group('篇数修改弹窗流', () {
    testWidgets('点击 + → 确认弹窗（当前 3 → 4）→ 确认修改', (tester) async {
      await pumpScreen(tester);

      // 两个 stepper（篇数 + 阈值）都有 + 按钮：取篇数那个（find.byIcon 顺序）
      await tester.tap(find.text('+').first);
      await tester.pumpAndSettle();
      expect(find.text('修改每日文章数量'), findsOneWidget);
      expect(find.textContaining('当前：3篇 → 调整至：4篇'), findsOneWidget);

      await tester.tap(find.text('确认修改'));
      await tester.pumpAndSettle();

      expect(settingsRepo.updates, contains('count:4'));
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('ℹ️ 信息弹窗', () {
    testWidgets('点击 ℹ️ → 信息弹窗 → 知道了关闭', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('ℹ').first);
      await tester.pumpAndSettle();

      expect(find.text('英文水平'), findsNWidgets(2)); // 设置项 + 弹窗标题
      expect(
        find.text('难度和篇数的修改将在第二天自动生效，不会影响今天的学习。'),
        findsOneWidget,
      );

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AppModal), findsNothing);
    });
  });

  group('朗读音色', () {
    testWidgets('音色行显示当前值，弹窗 8 项可选，选择后行值更新', (tester) async {
      await pumpScreen(tester);

      expect(find.text('朗读音色'), findsOneWidget);
      expect(find.text('贝拉 · Bella'), findsOneWidget);

      await tester.tap(find.text('贝拉 · Bella'));
      await tester.pumpAndSettle();
      expect(find.text('选择朗读音色'), findsOneWidget);

      // 8 个音色标签（bella 同时在设置行 + 弹窗行，共 2 处）
      for (final voice in TtsVoice.values) {
        final count = voice == TtsVoice.bella ? 2 : 1;
        expect(find.text(voice.label), findsNWidgets(count));
      }

      await tester.tap(find.text('露娜 · Luna'));
      await tester.pumpAndSettle();

      expect(settingsRepo.updates, contains('voice:LUNA'));
      expect(find.text('选择朗读音色'), findsNothing);
      expect(find.text('露娜 · Luna'), findsOneWidget); // 行值已更新
      expect(find.text('贝拉 · Bella'), findsNothing);
    });

    testWidgets('试听：8 个喇叭图标，点击播放固定例句（bella）', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('贝拉 · Bella'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_down_outlined), findsNWidgets(8));

      await tester.tap(find.byIcon(Icons.volume_down_outlined).first);
      await tester.pumpAndSettle();

      expect(tts.spoken, ['Hi, this is Bella speaking.']);
      expect(tts.spokenVoices, [TtsVoice.bella]);
      // 播放中的行高亮为 volume_up，其余 7 行仍为 volume_down_outlined
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.volume_down_outlined), findsNWidgets(7));
    });

    testWidgets('试听后选择音色 → 弹窗关闭且引擎 stop 被调用（关闭即停）', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('贝拉 · Bella'));
      await tester.pumpAndSettle();

      // 试听 bella
      await tester.tap(find.byIcon(Icons.volume_down_outlined).first);
      await tester.pumpAndSettle();
      expect(tts.spoken, ['Hi, this is Bella speaking.']);
      expect(tts.stopCount, 0);

      // 直接选择音色关闭弹窗（onSelect 路径，不经过 _stopPreviewAndDismiss）：
      // dispose 必须停掉正在试听的例句
      await tester.tap(find.text('露娜 · Luna'));
      await tester.pumpAndSettle();

      expect(find.text('选择朗读音色'), findsNothing);
      expect(tts.stopCount, 1);
      expect(settingsRepo.updates, contains('voice:LUNA'));
    });
  });

  group('退出登录', () {
    // 退出区位于 ListView 末尾，默认测试视口（600px）外不构建——
    // 先 scrollUntilVisible 滚动到「退出登录」再断言/交互。
    Future<void> scrollToLogout(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('退出登录'), 200);
      await tester.pumpAndSettle();
    }

    testWidgets('已登录：显示当前账号手机号 + 退出登录按钮', (tester) async {
      await seedLoggedIn(tester, '13800000000');
      await pumpScreen(tester);
      await scrollToLogout(tester);

      expect(find.textContaining('13800000000'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
    });

    testWidgets('点击退出登录 → 确认弹窗 → 确认 → 调 /api/auth/logout + 按钮消失',
        (tester) async {
      await seedLoggedIn(tester, '13800000000');
      await pumpScreen(tester);
      await scrollToLogout(tester);

      // 确认前先把 stub 切为登出响应（区分 login / logout 语义）
      adapter.handler = (options) async =>
          _json(200, {'code': 0, 'data': null});
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();

      expect(find.text('退出后本地学习数据保留，可随时重新登录。'), findsOneWidget);

      await tester.tap(find.text('退出')); // 弹窗确认按钮（red）
      await tester.pumpAndSettle();

      expect(adapter.lastRequest!.uri.path, '/api/auth/logout');
      expect(adapter.lastRequest!.data, {'device_id': 'dev-1'});
      expect(authService.status, AuthStatus.loggedOut);
      expect(find.text('退出登录'), findsNothing);
      expect(find.textContaining('13800000000'), findsNothing);
    });

    testWidgets('确认弹窗点取消 → 不调登出接口 + 按钮仍在', (tester) async {
      await seedLoggedIn(tester, '13800000000');
      await pumpScreen(tester);
      await scrollToLogout(tester);

      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();

      // 取消路径不应触发任何请求
      adapter.handler = (options) async =>
          throw StateError('取消不应调用接口: ${options.uri}');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(authService.status, AuthStatus.loggedIn);
      expect(find.text('退出登录'), findsOneWidget);
    });

    testWidgets('未登录：不显示退出按钮', (tester) async {
      await pumpScreen(tester);

      expect(find.text('退出登录'), findsNothing);
      expect(find.textContaining('13800000000'), findsNothing);
    });
  });
}
