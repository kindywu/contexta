import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo(this.settings);
  UserSettings? settings;
  @override
  Future<UserSettings?> getSettings() async => settings;
  // 其余方法：unsupported（throw UnimplementedError）
  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();
  @override
  Future<bool> isOnboarded() async => false;
  @override
  Future<void> completeOnboarding(String level, int dailyCount) async {}
  @override
  Future<void> updateLevel(String level) async {}
  @override
  Future<bool> updateDailyArticleCount(int newCount) async => true;
  @override
  Future<void> updateTranslationMode(String mode) async {}
  @override
  Future<void> updateTtsSpeed(double speed) async {}
  @override
  Future<void> updateTtsVoice(TtsVoice voice) async {}
  @override
  Future<void> updateMasteryThreshold(int n) async {}
  @override
  Future<void> updateAutoPlayAudio(bool enabled) async {}
  @override
  Future<void> saveAuth({
    required String phone,
    required String token,
    required int tokenExpiresAtMillis,
  }) async {}
  @override
  Future<void> clearAuth() async {}
}

void main() {
  test('从 settings 读当前音色', () async {
    final container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(
          _FakeSettingsRepo(const UserSettings(ttsVoice: TtsVoice.hugo))),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(currentTtsVoiceProvider.future), TtsVoice.hugo);
  });

  test('无 settings 行时默认 bella', () async {
    final container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo(null)),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(currentTtsVoiceProvider.future), TtsVoice.bella);
  });
}
