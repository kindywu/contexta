import '../model/tts_voice.dart';
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

  /// 更新朗读语速（UI 显示语速：0.8 / 1.0 / 1.2）。
  Future<void> updateTtsSpeed(double speed);

  /// 更新朗读音色（下次朗读生效，不打断当前播放）。
  Future<void> updateTtsVoice(TtsVoice voice);

  /// 夹取 1..5 后更新。
  Future<void> updateMasteryThreshold(int n);

  Future<void> updateAutoPlayAudio(bool enabled);

  /// 登录态持久化（user_settings 的 server_phone / server_token /
  /// server_token_expires_at；[tokenExpiresAtMillis] 为 Unix 毫秒）。
  Future<void> saveAuth({
    required String phone,
    required String token,
    required int tokenExpiresAtMillis,
  });

  /// 清除登录态（3 列置 null）。
  Future<void> clearAuth();
}
