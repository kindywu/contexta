import 'package:contexta/domain/model/daily_stats.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/ui/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings 页 controller 测试（Task 26）。
/// 对照 Kotlin SettingsViewModel 的行为契约：
/// - 加载设置 + 统计
/// - ℹ️ 信息弹窗开合
/// - 难度修改：request → confirm（持久化 + 触发生成）/ cancel
/// - 篇数修改：request（边界校验）→ confirm（仅写 DB）/ cancel
/// - 译文模式 / 掌握阈值（1..5 夹取）/ 自动朗读 直接持久化

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo({UserSettings? settings})
      : _settings = settings ?? const UserSettings(isOnboarded: true);

  UserSettings _settings;
  final List<String> updates = [];

  @override
  Future<UserSettings?> getSettings() async => _settings;

  @override
  Future<void> updateLevel(String level) async {
    updates.add('level:$level');
    _settings = UserSettings(
      isOnboarded: _settings.isOnboarded,
      difficultyLevel: level,
      dailyArticleCount: _settings.dailyArticleCount,
      translationDisplayMode: _settings.translationDisplayMode,
      masteryThresholdN: _settings.masteryThresholdN,
      autoPlayAudio: _settings.autoPlayAudio,
    );
  }

  @override
  Future<bool> updateDailyArticleCount(int newCount) async {
    updates.add('count:$newCount');
    _settings = UserSettings(
      isOnboarded: _settings.isOnboarded,
      difficultyLevel: _settings.difficultyLevel,
      dailyArticleCount: newCount,
      translationDisplayMode: _settings.translationDisplayMode,
      masteryThresholdN: _settings.masteryThresholdN,
      autoPlayAudio: _settings.autoPlayAudio,
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
    _settings = UserSettings(
      isOnboarded: _settings.isOnboarded,
      difficultyLevel: _settings.difficultyLevel,
      dailyArticleCount: _settings.dailyArticleCount,
      translationDisplayMode: mode,
      masteryThresholdN: _settings.masteryThresholdN,
      autoPlayAudio: _settings.autoPlayAudio,
    );
  }

  @override
  Future<void> updateMasteryThreshold(int n) async {
    updates.add('threshold:$n');
    _settings = UserSettings(
      isOnboarded: _settings.isOnboarded,
      difficultyLevel: _settings.difficultyLevel,
      dailyArticleCount: _settings.dailyArticleCount,
      translationDisplayMode: _settings.translationDisplayMode,
      masteryThresholdN: n,
      autoPlayAudio: _settings.autoPlayAudio,
    );
  }

  @override
  Future<void> updateAutoPlayAudio(bool enabled) async {
    updates.add('autoPlay:$enabled');
    _settings = UserSettings(
      isOnboarded: _settings.isOnboarded,
      difficultyLevel: _settings.difficultyLevel,
      dailyArticleCount: _settings.dailyArticleCount,
      translationDisplayMode: _settings.translationDisplayMode,
      masteryThresholdN: _settings.masteryThresholdN,
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
  late SettingsController controller;

  Future<SettingsController> createController({
    UserSettings? settings,
    DailyStats? stats,
  }) async {
    settingsRepo = _FakeSettingsRepo(settings: settings);
    statsRepo = _FakeStatsRepo(stats: stats);
    triggered = [];
    final c = SettingsController(
      settingsRepository: settingsRepo,
      statsRepository: statsRepo,
      triggerNextBatch: (String difficulty, int dailyCount) async {
        triggered.add('$difficulty:$dailyCount');
      },    );
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  tearDown(() {
    controller.dispose();
  });

  group('加载', () {
    test('有设置 + 统计 → 填充状态', () async {
      controller = await createController(
        settings: const UserSettings(
          isOnboarded: true,
          difficultyLevel: 'HIGH',
          dailyArticleCount: 4,
          translationDisplayMode: 'DIM',
          masteryThresholdN: 3,
          autoPlayAudio: true,
        ),
        stats: _stats,
      );

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.level, 'HIGH');
      expect(controller.state.dailyCount, 4);
      expect(controller.state.translationMode, 'DIM');
      expect(controller.state.masteryThreshold, 3);
      expect(controller.state.autoPlayAudio, isTrue);
      expect(controller.state.stats.totalArticlesRead, 12);
      expect(controller.state.stats.totalWordsAdded, 34);
      expect(controller.state.stats.totalWordsMastered, 5);
      expect(controller.state.stats.totalLearningDays, 6);
      expect(controller.state.stats.currentStreak, 3);
      expect(controller.state.stats.longestStreak, 7);
    });

    test('无设置 → 空状态（isLoading=false，默认值）', () async {
      controller = await createController(settings: null);

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.level, 'MEDIUM');
      expect(controller.state.dailyCount, 3);
    });

    test('无统计 → 统计全 0', () async {
      controller = await createController(stats: null);

      expect(controller.state.stats.totalArticlesRead, 0);
      expect(controller.state.stats.currentStreak, 0);
    });
  });

  group('ℹ️ 信息弹窗', () {
    test('showLevelInfo / showCountInfo / dismissInfoDialog', () async {
      controller = await createController();

      controller.showLevelInfo();
      expect(controller.state.showLevelInfoDialog, isTrue);

      controller.dismissInfoDialog();
      expect(controller.state.showLevelInfoDialog, isFalse);

      controller.showCountInfo();
      expect(controller.state.showCountInfoDialog, isTrue);

      controller.dismissInfoDialog();
      expect(controller.state.showCountInfoDialog, isFalse);
    });
  });

  group('难度修改', () {
    test('选择新难度 → 暂存 + 弹确认弹窗', () async {
      controller = await createController();

      controller.requestLevelChange('HIGH');

      expect(controller.state.pendingLevel, 'HIGH');
      expect(controller.state.showLevelConfirmDialog, isTrue);
      // 尚未生效
      expect(controller.state.level, 'MEDIUM');
    });

    test('选择当前难度 → 忽略', () async {
      controller = await createController();

      controller.requestLevelChange('MEDIUM');

      expect(controller.state.showLevelConfirmDialog, isFalse);
      expect(controller.state.pendingLevel, isNull);
    });

    test('确认修改 → 持久化 + 触发生成 + 关闭弹窗', () async {
      controller = await createController();
      controller.requestLevelChange('HIGH');
      await controller.confirmLevelChange();

      expect(settingsRepo.updates, contains('level:HIGH'));
      expect(triggered, ['HIGH:3']); // dailyCount 3
      expect(controller.state.level, 'HIGH');
      expect(controller.state.showLevelConfirmDialog, isFalse);
      expect(controller.state.pendingLevel, isNull);
    });

    test('取消修改 → 关闭弹窗且不生效', () async {
      controller = await createController();
      controller.requestLevelChange('HIGH');

      controller.cancelLevelChange();

      expect(controller.state.showLevelConfirmDialog, isFalse);
      expect(controller.state.pendingLevel, isNull);
      expect(controller.state.level, 'MEDIUM');
      expect(settingsRepo.updates, isEmpty);
      expect(triggered, isEmpty);
    });
  });

  group('篇数修改', () {
    test('点击 ± → 暂存 + 弹确认弹窗', () async {
      controller = await createController();

      controller.requestCountChange(4);

      expect(controller.state.pendingCount, 4);
      expect(controller.state.showCountConfirmDialog, isTrue);
      expect(controller.state.dailyCount, 3);
    });

    test('越界值（0 / 6）忽略', () async {
      controller = await createController();

      controller.requestCountChange(0);
      controller.requestCountChange(6);

      expect(controller.state.showCountConfirmDialog, isFalse);
      expect(controller.state.pendingCount, isNull);
    });

    test('未变更（等于当前值）忽略', () async {
      controller = await createController();

      controller.requestCountChange(3);

      expect(controller.state.showCountConfirmDialog, isFalse);
    });

    test('确认修改 → 仅写 DB（不触发生成）', () async {
      controller = await createController();
      controller.requestCountChange(5);
      await controller.confirmCountChange();

      expect(settingsRepo.updates, contains('count:5'));
      expect(triggered, isEmpty); // 篇数不触发新批次
      expect(controller.state.dailyCount, 5);
      expect(controller.state.showCountConfirmDialog, isFalse);
      expect(controller.state.pendingCount, isNull);
    });

    test('取消修改 → 关闭弹窗且不生效', () async {
      controller = await createController();
      controller.requestCountChange(4);

      controller.cancelCountChange();

      expect(controller.state.showCountConfirmDialog, isFalse);
      expect(controller.state.pendingCount, isNull);
      expect(controller.state.dailyCount, 3);
      expect(settingsRepo.updates, isEmpty);
    });
  });

  group('直接持久化设置', () {
    test('译文模式', () async {
      controller = await createController();

      await controller.updateTranslationMode('HIDDEN');

      expect(settingsRepo.updates, contains('mode:HIDDEN'));
      expect(controller.state.translationMode, 'HIDDEN');
    });

    test('掌握阈值递增（上限 5 夹取）', () async {
      controller = await createController(
        settings: const UserSettings(isOnboarded: true, masteryThresholdN: 4),
      );

      await controller.incrementMasteryThreshold();
      expect(controller.state.masteryThreshold, 5);
      expect(settingsRepo.updates, contains('threshold:5'));

      await controller.incrementMasteryThreshold(); // 已到上限
      expect(controller.state.masteryThreshold, 5);
      expect(settingsRepo.updates.where((u) => u == 'threshold:5').length, 1);
    });

    test('掌握阈值递减（下限 1 夹取）', () async {
      controller = await createController();

      await controller.decrementMasteryThreshold(); // 1 → 下限
      expect(controller.state.masteryThreshold, 1);
      expect(settingsRepo.updates, isEmpty);

      await controller.incrementMasteryThreshold();
      await controller.decrementMasteryThreshold();
      expect(controller.state.masteryThreshold, 1);
    });

    test('自动朗读开关', () async {
      controller = await createController();

      await controller.toggleAutoPlayAudio();
      expect(controller.state.autoPlayAudio, isTrue);
      expect(settingsRepo.updates, contains('autoPlay:true'));

      await controller.toggleAutoPlayAudio();
      expect(controller.state.autoPlayAudio, isFalse);
    });
  });
}
