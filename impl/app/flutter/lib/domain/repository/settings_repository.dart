import '../model/user_settings.dart';

/// 设置仓储接口（对齐 Kotlin SettingsRepository.kt）。
abstract interface class SettingsRepository {
  /// 观察设置（单例行 id=1；无记录时发射 null）。
  Stream<UserSettings?> observeSettings();

  Future<UserSettings?> getSettings();

  Future<bool> isOnboarded();

  Future<void> completeOnboarding(String level, int dailyCount);

  Future<void> updateLevel(String level);

  /// 校验 1..5 且值变化才更新。返回是否已更新。
  Future<bool> updateDailyArticleCount(int newCount);

  Future<void> updateTranslationMode(String mode);

  /// 夹取 1..5 后更新。
  Future<void> updateMasteryThreshold(int n);

  Future<void> updateAutoPlayAudio(bool enabled);
}
