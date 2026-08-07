import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/usecase/activate_seed_batch_usecase.dart';

/// Onboarding 步骤状态（对照 Kotlin OnboardingState）。
class OnboardingState {
  const OnboardingState({
    this.currentStep = 1,
    this.selectedLevel,
    this.selectedDailyCount,
  });

  final int currentStep; // 1..3
  final String? selectedLevel; // LOW | MEDIUM | HIGH
  final int? selectedDailyCount; // 1 | 3 | 5

  OnboardingState copyWith({
    int? currentStep,
    String? selectedLevel,
    int? selectedDailyCount,
  }) =>
      OnboardingState(
        currentStep: currentStep ?? this.currentStep,
        selectedLevel: selectedLevel ?? this.selectedLevel,
        selectedDailyCount: selectedDailyCount ?? this.selectedDailyCount,
      );

  /// 当前步是否可推进（UI 按钮禁用依据）。
  bool get canProceed => switch (currentStep) {
        1 => selectedLevel != null,
        2 => selectedDailyCount != null,
        3 => true,
        _ => false,
      };
}

/// Onboarding 控制器（对照 Kotlin OnboardingViewModel）：
/// 3 步向导状态机 + 完成时写入设置并激活种子批次。
class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController({
    required this._settingsRepository,
    required this._activateSeedBatch,
  }) : super(const OnboardingState());

  final SettingsRepository _settingsRepository;
  final ActivateSeedBatchUseCase _activateSeedBatch;

  void selectLevel(String level) =>
      state = state.copyWith(selectedLevel: level);

  void selectDailyCount(int count) =>
      state = state.copyWith(selectedDailyCount: count);

  void nextStep() {
    if (state.currentStep < 3) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void previousStep() {
    if (state.currentStep > 1) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  /// 完成引导：写入设置 + 激活种子批次（用户立即看到初始文章），
  /// 然后回调通知导航跳 Home（context.go('/home') 清栈）。
  Future<void> completeOnboarding(VoidCallback onComplete) async {
    final level = state.selectedLevel;
    final dailyCount = state.selectedDailyCount;
    if (level == null || dailyCount == null) return;

    await _settingsRepository.completeOnboarding(level, dailyCount);
    await _activateSeedBatch(level, dailyCount);
    onComplete();
  }

  /// 启动时检查：用户已完成引导则跳过。
  Future<bool> isAlreadyOnboarded() => _settingsRepository.isOnboarded();
}

/// Onboarding 控制器 Provider。
final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
  return OnboardingController(
    settingsRepository: ref.watch(settingsRepositoryProvider),
    activateSeedBatch: ref.watch(activateSeedBatchUseCaseProvider),
  );
});
