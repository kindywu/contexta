import 'package:contexta/di/providers.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/usecase/activate_seed_batch_usecase.dart';
import 'package:contexta/main.dart';
import 'package:contexta/ui/onboarding/onboarding_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 启动冒烟测试：真实路由表 + 主题接入，落在 Onboarding 页。
/// （Task 29 修复后为真实页而非占位页；仓储用空桩避免触达真实数据库。）

class _FakeSettingsRepo implements SettingsRepository {
  @override
  Stream<UserSettings?> observeSettings() => const Stream.empty();

  @override
  Future<UserSettings?> getSettings() async => null;

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
  Future<void> updateMasteryThreshold(int n) async {}

  @override
  Future<void> updateAutoPlayAudio(bool enabled) async {}
}

class _FakeActivateSeedBatch implements ActivateSeedBatchUseCase {
  @override
  Future<bool> call(String difficulty, int dailyCount) async => true;
}

void main() {
  testWidgets('App 启动渲染 Onboarding（MaterialApp.router + 主题接入）',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
        activateSeedBatchUseCaseProvider.overrideWithValue(
            _FakeActivateSeedBatch()),
      ],
      child: const MainApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Contexta'), findsOneWidget);
  });
}
