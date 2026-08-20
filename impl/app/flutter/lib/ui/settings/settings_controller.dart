import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/model/tts_voice.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/repository/stats_repository.dart';
import '../../domain/tts/tts_engine.dart';

/// Settings 页 UI 状态（对照 Kotlin SettingsUiState）。
class SettingsUiState {
  const SettingsUiState({
    this.level = 'MEDIUM',
    this.dailyCount = 3,
    this.translationMode = 'FULL',
    this.ttsSpeed = 1.0,
    this.ttsVoice = TtsVoice.bella,
    this.masteryThreshold = 1,
    this.autoPlayAudio = false,
    this.stats = const SettingsStatsData(),
    this.isLoading = true,
    this.showLevelInfoDialog = false,
    this.showCountInfoDialog = false,
    this.showLevelConfirmDialog = false,
    this.showCountConfirmDialog = false,
    this.pendingLevel,
    this.pendingCount,
  });

  final String level;
  final int dailyCount;
  final String translationMode;
  final double ttsSpeed;
  final TtsVoice ttsVoice;
  final int masteryThreshold;
  final bool autoPlayAudio;
  final SettingsStatsData stats;
  final bool isLoading;

  /// ℹ️ 信息弹窗（对照 Kotlin showLevelInfoDialog / showCountInfoDialog）。
  final bool showLevelInfoDialog;
  final bool showCountInfoDialog;

  /// 确认弹窗（设置次日生效，对照 Kotlin showLevelConfirmDialog /
  /// showCountConfirmDialog）。
  final bool showLevelConfirmDialog;
  final bool showCountConfirmDialog;

  /// 暂存待确认的难度 / 篇数。
  final String? pendingLevel;
  final int? pendingCount;

  SettingsUiState copyWith({
    String? level,
    int? dailyCount,
    String? translationMode,
    double? ttsSpeed,
    TtsVoice? ttsVoice,
    int? masteryThreshold,
    bool? autoPlayAudio,
    SettingsStatsData? stats,
    bool? isLoading,
    bool? showLevelInfoDialog,
    bool? showCountInfoDialog,
    bool? showLevelConfirmDialog,
    bool? showCountConfirmDialog,
    Object? pendingLevel = _unset,
    Object? pendingCount = _unset,
  }) =>
      SettingsUiState(
        level: level ?? this.level,
        dailyCount: dailyCount ?? this.dailyCount,
        translationMode: translationMode ?? this.translationMode,
        ttsSpeed: ttsSpeed ?? this.ttsSpeed,
        ttsVoice: ttsVoice ?? this.ttsVoice,
        masteryThreshold: masteryThreshold ?? this.masteryThreshold,
        autoPlayAudio: autoPlayAudio ?? this.autoPlayAudio,
        stats: stats ?? this.stats,
        isLoading: isLoading ?? this.isLoading,
        showLevelInfoDialog:
            showLevelInfoDialog ?? this.showLevelInfoDialog,
        showCountInfoDialog:
            showCountInfoDialog ?? this.showCountInfoDialog,
        showLevelConfirmDialog:
            showLevelConfirmDialog ?? this.showLevelConfirmDialog,
        showCountConfirmDialog:
            showCountConfirmDialog ?? this.showCountConfirmDialog,
        pendingLevel: identical(pendingLevel, _unset)
            ? this.pendingLevel
            : pendingLevel as String?,
        pendingCount: identical(pendingCount, _unset)
            ? this.pendingCount
            : pendingCount as int?,
      );

  static const Object _unset = Object();
}

/// 学习统计（对照 Kotlin StatsData）。
class SettingsStatsData {
  const SettingsStatsData({
    this.totalArticlesRead = 0,
    this.totalWordsAdded = 0,
    this.totalWordsMastered = 0,
    this.totalLearningDays = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
  });

  final int totalArticlesRead;
  final int totalWordsAdded;
  final int totalWordsMastered;
  final int totalLearningDays;
  final int currentStreak;
  final int longestStreak;
}

/// Settings 页控制器（对照 Kotlin SettingsViewModel）：
/// - 进入加载设置 + 统计
/// - ℹ️ 信息弹窗（难度/篇数次日生效）
/// - 难度修改：选择 → 确认弹窗 → 持久化（2026-08-13 T6：不再触发本地生成，
///   新难度文章由下一次服务端同步提供）
/// - 篇数修改：± → 确认弹窗 → 持久化（仅写 DB，不触发生成）
/// - 译文模式 / 掌握阈值 / 自动朗读：直接持久化
class SettingsController extends StateNotifier<SettingsUiState> {
  SettingsController({
    required this._settingsRepository,
    required this._statsRepository,
    required this._ttsEngineFuture,
    this.onTtsVoiceChanged,
  }) : super(const SettingsUiState()) {
    loadSettings();
  }

  final SettingsRepository _settingsRepository;
  final StatsRepository _statsRepository;
  final Future<TtsEngine> _ttsEngineFuture;

  /// 音色变更回调：持久化成功后调用（生产接线 invalidate
  /// currentTtsVoiceProvider，使下次朗读立即用新音色；测试可注入断言）。
  final void Function()? onTtsVoiceChanged;

  /// 试听引擎（弹窗试听用）。
  Future<TtsEngine> get engineFuture => _ttsEngineFuture;

  Future<void> loadSettings() async {
    final settings = await _settingsRepository.getSettings();
    final stats = await _statsRepository.getStats();

    if (settings == null) {
      state = const SettingsUiState(isLoading: false);
      return;
    }
    state = SettingsUiState(
      level: settings.difficultyLevel,
      dailyCount: settings.dailyArticleCount,
      translationMode: settings.translationDisplayMode,
      ttsSpeed: settings.ttsSpeed,
      ttsVoice: settings.ttsVoice,
      masteryThreshold: settings.masteryThresholdN,
      autoPlayAudio: settings.autoPlayAudio,
      stats: SettingsStatsData(
        totalArticlesRead: stats?.totalArticlesRead ?? 0,
        totalWordsAdded: stats?.totalWordsAdded ?? 0,
        totalWordsMastered: stats?.totalWordsMastered ?? 0,
        totalLearningDays: stats?.totalLearningDays ?? 0,
        currentStreak: stats?.currentStreak ?? 0,
        longestStreak: stats?.longestStreak ?? 0,
      ),
      isLoading: false,
    );
  }

  // ── ℹ️ 信息弹窗 ──

  void showLevelInfo() {
    state = state.copyWith(showLevelInfoDialog: true);
  }

  void showCountInfo() {
    state = state.copyWith(showCountInfoDialog: true);
  }

  void dismissInfoDialog() {
    state = state.copyWith(
      showLevelInfoDialog: false,
      showCountInfoDialog: false,
    );
  }

  // ── 难度修改：选择 → 确认 → 持久化（次日生效） ──

  /// 用户选择新难度后调用：暂存并弹出确认弹窗（未变更则忽略）。
  void requestLevelChange(String level) {
    if (level == state.level) return;
    state = state.copyWith(
      pendingLevel: level,
      showLevelConfirmDialog: true,
    );
  }

  /// 用户确认修改难度：持久化（次日生效；新难度文章由下一次服务端同步提供，
  /// 2026-08-13 T6 起不再触发本地生成）。
  Future<void> confirmLevelChange() async {
    final level = state.pendingLevel;
    if (level == null) return;
    await _settingsRepository.updateLevel(level);
    state = state.copyWith(
      level: level,
      showLevelConfirmDialog: false,
      pendingLevel: null,
    );
  }

  /// 用户取消修改难度。
  void cancelLevelChange() {
    state = state.copyWith(
      showLevelConfirmDialog: false,
      pendingLevel: null,
    );
  }

  // ── 篇数修改：± → 确认 → 持久化（不触发生成）──

  /// 用户点击 ± 后调用：暂存并弹出确认弹窗（越界/未变更则忽略）。
  void requestCountChange(int newCount) {
    if (newCount < 1 || newCount > 5) return;
    if (newCount == state.dailyCount) return;
    state = state.copyWith(
      pendingCount: newCount,
      showCountConfirmDialog: true,
    );
  }

  /// 用户确认修改篇数：仅写 DB，不触发新批次生成。
  /// （篇数变化在下一次分配批次时通过 dailyCountSnapshot 体现。）
  Future<void> confirmCountChange() async {
    final count = state.pendingCount;
    if (count == null) return;
    await _settingsRepository.updateDailyArticleCount(count);
    state = state.copyWith(
      dailyCount: count,
      showCountConfirmDialog: false,
      pendingCount: null,
    );
  }

  /// 用户取消修改篇数。
  void cancelCountChange() {
    state = state.copyWith(
      showCountConfirmDialog: false,
      pendingCount: null,
    );
  }

  Future<void> updateTranslationMode(String mode) async {
    await _settingsRepository.updateTranslationMode(mode);
    state = state.copyWith(translationMode: mode);
  }

  Future<void> updateTtsSpeed(double speed) async {
    await _settingsRepository.updateTtsSpeed(speed);
    state = state.copyWith(ttsSpeed: speed);
  }

  /// 更新朗读音色：写库成功后更新状态并回调（未变更则忽略）。
  Future<void> updateTtsVoice(TtsVoice voice) async {
    if (voice == state.ttsVoice) return;
    await _settingsRepository.updateTtsVoice(voice);
    state = state.copyWith(ttsVoice: voice);
    onTtsVoiceChanged?.call();
  }

  Future<void> incrementMasteryThreshold() async {
    final newValue = state.masteryThreshold + 1;
    if (newValue > 5) return;
    await _settingsRepository.updateMasteryThreshold(newValue);
    state = state.copyWith(masteryThreshold: newValue);
  }

  Future<void> decrementMasteryThreshold() async {
    final newValue = state.masteryThreshold - 1;
    if (newValue < 1) return;
    await _settingsRepository.updateMasteryThreshold(newValue);
    state = state.copyWith(masteryThreshold: newValue);
  }

  Future<void> toggleAutoPlayAudio() async {
    final newValue = !state.autoPlayAudio;
    await _settingsRepository.updateAutoPlayAudio(newValue);
    state = state.copyWith(autoPlayAudio: newValue);
  }
}

/// Settings 页控制器 Provider。
final settingsControllerProvider =
    StateNotifierProvider.autoDispose<SettingsController, SettingsUiState>(
        (ref) {
  return SettingsController(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    statsRepository: ref.watch(statsRepositoryProvider),
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
    // 音色写库后失效缓存，参考页/词汇页/朗读下次读取即新音色
    onTtsVoiceChanged: () => ref.invalidate(currentTtsVoiceProvider),
  );
});
