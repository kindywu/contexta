import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_button.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'onboarding_controller.dart';

/// Onboarding 引导页（对照 Kotlin OnboardingScreen.kt）：
/// 3 步向导（水平 → 每日篇数 → 确认），底部进度点 + 上一步/下一步按钮。
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key, this.onComplete});

  /// 完成引导后的跳转回调（由路由层注入：context.go('/home')）。
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 品牌区
            const SizedBox(height: 40),
            Text(
              'Contexta',
              textAlign: TextAlign.center,
              style: AppType.textTheme.displayLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '语境 · 沉浸式英语阅读',
              textAlign: TextAlign.center,
              style: AppType.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 32),

            // 步骤内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: switch (state.currentStep) {
                  1 => _Step1Level(
                      selectedLevel: state.selectedLevel,
                      onSelectLevel: ref
                          .read(onboardingControllerProvider.notifier)
                          .selectLevel,
                    ),
                  2 => _Step2DailyCount(
                      selectedDailyCount: state.selectedDailyCount,
                      onSelectCount: ref
                          .read(onboardingControllerProvider.notifier)
                          .selectDailyCount,
                    ),
                  _ => _Step3Confirmation(
                      level: state.selectedLevel ?? '',
                      dailyCount: state.selectedDailyCount ?? 0,
                    ),
                },
              ),
            ),

            // 底部操作区
            Column(
              children: [
                _ProgressDots(currentStep: state.currentStep),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      if (state.currentStep > 1) ...[
                        Expanded(
                          child: AppButton(
                            text: '上一步',
                            variant: AppButtonVariant.secondary,
                            onClick: ref
                                .read(onboardingControllerProvider.notifier)
                                .previousStep,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: AppButton(
                          text: state.currentStep < 3 ? '下一步' : '开始学习',
                          enabled: state.canProceed,
                          onClick: () {
                            final controller =
                                ref.read(onboardingControllerProvider.notifier);
                            if (state.currentStep < 3) {
                              controller.nextStep();
                            } else {
                              controller.completeOnboarding(
                                  onComplete ?? () {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 第 1 步：选择英文水平。
class _Step1Level extends StatelessWidget {
  const _Step1Level({required this.selectedLevel, required this.onSelectLevel});

  final String? selectedLevel;
  final ValueChanged<String> onSelectLevel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择你的英文水平', style: AppType.textTheme.displayMedium),
        const SizedBox(height: 24),
        _LevelOption(
          label: '初级 · LOW',
          desc: '小学、初中水平，从基础开始',
          isSelected: selectedLevel == 'LOW',
          onClick: () => onSelectLevel('LOW'),
          icon: Icons.school_outlined,
        ),
        _LevelOption(
          label: '中级 · MEDIUM',
          desc: '高中、大学四六级水平',
          isSelected: selectedLevel == 'MEDIUM',
          onClick: () => onSelectLevel('MEDIUM'),
          icon: Icons.auto_stories_outlined,
        ),
        _LevelOption(
          label: '高级 · HIGH',
          desc: '专八、托福、雅思水平',
          isSelected: selectedLevel == 'HIGH',
          onClick: () => onSelectLevel('HIGH'),
          icon: Icons.workspace_premium_outlined,
        ),
      ],
    );
  }
}

/// 第 2 步：每日文章数量。
class _Step2DailyCount extends StatelessWidget {
  const _Step2DailyCount({
    required this.selectedDailyCount,
    required this.onSelectCount,
  });

  final int? selectedDailyCount;
  final ValueChanged<int> onSelectCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每日文章数量', style: AppType.textTheme.displayMedium),
        const SizedBox(height: 4),
        Text(
          '每天为你生成几篇文章？',
          style: AppType.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        _CountOption(
          count: 1,
          label: '1 篇',
          desc: '轻松起步',
          isSelected: selectedDailyCount == 1,
          onClick: () => onSelectCount(1),
        ),
        _CountOption(
          count: 3,
          label: '3 篇',
          desc: '适中节奏',
          isSelected: selectedDailyCount == 3,
          onClick: () => onSelectCount(3),
        ),
        _CountOption(
          count: 5,
          label: '5 篇',
          desc: '充分练习',
          isSelected: selectedDailyCount == 5,
          onClick: () => onSelectCount(5),
        ),
      ],
    );
  }
}

/// 第 3 步：确认页。
class _Step3Confirmation extends StatelessWidget {
  const _Step3Confirmation({required this.level, required this.dailyCount});

  final String level;
  final int dailyCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('准备好了！', style: AppType.textTheme.displayMedium),
        const SizedBox(height: 4),
        Text(
          '系统将根据你的设置，每天推送匹配水平的英文文章。首次生成需要一些时间，请稍候。',
          style: AppType.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 40, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(
                '你的专属阅读之旅即将开始',
                style: AppType.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '每天坚持阅读，不知不觉提升英语',
                style: AppType.textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Text(
                '水平：${_levelLabel(level)}   |   每日 $dailyCount 篇',
                textAlign: TextAlign.center,
                style: AppType.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 水平/篇数选择卡片：选中 2dp Primary 边框 + SurfaceStrong 底 +
/// 22dp 圆形单选指示；未选中 Hairline 边框 + SurfaceCard 底。
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.label,
    required this.desc,
    required this.isSelected,
    required this.onClick,
    this.icon,
  });

  final String label;
  final String desc;
  final bool isSelected;
  final VoidCallback onClick;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? AppColors.primary : AppColors.hairline;
    final bgColor = isSelected ? AppColors.surfaceStrong : AppColors.surfaceCard;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onClick,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 28,
                      color: isSelected ? AppColors.primary : AppColors.mutedSoft),
                  const SizedBox(width: 10),
                ],
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.hairline,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppType.textTheme.titleMedium),
                      Text(
                        desc,
                        style: AppType.textTheme.bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelOption extends StatelessWidget {
  const _LevelOption({
    required this.label,
    required this.desc,
    required this.isSelected,
    required this.onClick,
    required this.icon,
  });

  final String label;
  final String desc;
  final bool isSelected;
  final VoidCallback onClick;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _OptionCard(
        label: label,
        desc: desc,
        isSelected: isSelected,
        onClick: onClick,
        icon: icon,
      );
}

class _CountOption extends StatelessWidget {
  const _CountOption({
    required this.count,
    required this.label,
    required this.desc,
    required this.isSelected,
    required this.onClick,
  });

  final int count;
  final String label;
  final String desc;
  final bool isSelected;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) => _OptionCard(
        label: label,
        desc: desc,
        isSelected: isSelected,
        onClick: onClick,
      );
}

/// 3 点进度条：当前步 Primary 胶囊（24x8），已完成 Primary 40%，未到 Hairline。
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 3; i++) ...[
          if (i > 1) const SizedBox(width: 8),
          Container(
            width: i == currentStep ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: switch ((i, i < currentStep)) {
                (_, true) => AppColors.primary.withValues(alpha: 0.4),
                (_, false) when i == currentStep => AppColors.primary,
                _ => AppColors.hairline,
              },
              borderRadius: BorderRadius.circular(
                  i == currentStep ? 4 : 999),
            ),
          ),
        ],
      ],
    );
  }
}

String _levelLabel(String level) => switch (level) {
      'LOW' => '初级',
      'MEDIUM' => '中级',
      'HIGH' => '高级',
      _ => level,
    };
