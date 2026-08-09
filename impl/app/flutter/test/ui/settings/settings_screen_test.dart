import 'package:contexta/core/components/app_modal.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/daily_stats.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/usecase/trigger_next_batch_usecase.dart';
import 'package:contexta/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings 页 widget 测试（Task 26）。
/// 逻辑已由 settings_controller_test 覆盖（17 个），此处验证 UI 接线：
/// - tabs 切换（学习设置 / 学习统计 + 统计卡片）
/// - 设置项渲染（picker 值 / stepper / 开关）
/// - 弹窗流：选择器 → 确认修改；ℹ️ → 信息弹窗；取消
/// - 路由接线（app_router_test 覆盖）

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
  @override
  Future<void> updateTtsSpeed(double speed) async {
    updates.add('ttsSpeed:$speed');
  }

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
  late List<String> triggered;

  setUp(() {
    settingsRepo = _FakeSettingsRepo();
    statsRepo = _FakeStatsRepo(stats: _stats);
    triggered = [];
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        statsRepositoryProvider.overrideWithValue(statsRepo),
        triggerNextBatchUseCaseProvider.overrideWith((ref) {
          return TriggerNextBatchStub(
            onCall: (difficulty, dailyCount) async =>
                triggered.add('$difficulty:$dailyCount'),
          );
        }),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
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
      expect(triggered, ['HIGH:3']);
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
      expect(triggered, isEmpty);
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
      expect(triggered, isEmpty); // 篇数不触发生成
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
}

/// TriggerNextBatchUseCase 桩（记录调用参数）。
class TriggerNextBatchStub implements TriggerNextBatchUseCase {
  TriggerNextBatchStub({required this.onCall});

  final Future<void> Function(String difficulty, int dailyCount) onCall;

  @override
  Future<void> call(String difficulty, int dailyCount) =>
      onCall(difficulty, dailyCount);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}
