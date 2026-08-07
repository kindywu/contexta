import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_modal.dart';
import '../../core/components/loading_indicator.dart';
import '../../core/components/stat_card.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'settings_controller.dart';

/// Settings 页（对照 Kotlin SettingsScreen.kt）：
/// - 顶部 InlineTabs：「学习设置」/「学习统计」
/// - 学习设置：英文水平（选择器 + ℹ️）、每日文章数量（± stepper + ℹ️）、
///   译文默认模式（选择器）、单词掌握阈值（± stepper）、自动朗读（开关）
/// - 学习统计：2×2 StatCard（阅读文章/添加单词/累计学习天数/当前连续学习）
/// - 弹窗：选择器（radio 列表）、ℹ️ 信息、确认修改（次日生效）
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedTab = 0;

  // 选择器弹窗的本地开关（对照 Kotlin remember 的 showLevelPicker /
  // showTranslationModePicker）
  bool _showLevelPicker = false;
  bool _showTranslationModePicker = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    if (state.isLoading) {
      return const SizedBox.expand(child: LoadingIndicator());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _InlineTabs(
                tabs: const ['学习设置', '学习统计'],
                selectedIndex: _selectedTab,
                onSelect: (index) => setState(() => _selectedTab = index),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  children: [
                    if (_selectedTab == 0)
                      _LearningSettingsContent(
                        state: state,
                        controller: controller,
                        onShowLevelPicker: () =>
                            setState(() => _showLevelPicker = true),
                        onShowTranslationModePicker: () => setState(
                            () => _showTranslationModePicker = true),
                      )
                    else
                      _StatsContent(stats: state.stats),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ],
          ),
          // ── 弹窗层（选择器 / ℹ️ 信息 / 确认修改）──
          ..._buildModals(state, controller),
        ],
      ),
    );
  }

  /// 组装全部弹窗（选择器 / ℹ️ 信息 / 确认修改）。
  List<Widget> _buildModals(
      SettingsUiState state, SettingsController controller) {
    return [
      if (_showLevelPicker)
        _SettingsPickerDialog(
          title: '选择英文水平',
          options: const [
            ('LOW', '初级'),
            ('MEDIUM', '中级'),
            ('HIGH', '高级'),
          ],
          selectedValue: state.level,
          onSelect: (level) {
            controller.requestLevelChange(level);
            setState(() => _showLevelPicker = false);
          },
          onDismiss: () => setState(() => _showLevelPicker = false),
        ),
      if (_showTranslationModePicker)
        _SettingsPickerDialog(
          title: '选择译文默认模式',
          options: const [
            ('FULL', '完全显示'),
            ('DIM', '淡化'),
            ('BLURRED', '模糊'),
            ('HIDDEN', '隐藏'),
          ],
          selectedValue: state.translationMode,
          onSelect: (mode) {
            controller.updateTranslationMode(mode);
            setState(() => _showTranslationModePicker = false);
          },
          onDismiss: () =>
              setState(() => _showTranslationModePicker = false),
        ),
      if (state.showLevelInfoDialog)
        _SettingsInfoDialog(
          title: '英文水平',
          message: '难度和篇数的修改将在第二天自动生效，不会影响今天的学习。',
          onConfirm: controller.dismissInfoDialog,
        ),
      if (state.showCountInfoDialog)
        _SettingsInfoDialog(
          title: '每日文章数量',
          message: '难度和篇数的修改将在第二天自动生效，不会影响今天的学习。',
          onConfirm: controller.dismissInfoDialog,
        ),
      if (state.showLevelConfirmDialog)
        _SettingsConfirmDialog(
          title: '修改英文水平',
          message: '此设置将在明天生效，今天的学习不受影响。',
          confirmLabel: '确认修改',
          onConfirm: controller.confirmLevelChange,
          onDismiss: controller.cancelLevelChange,
        ),
      if (state.showCountConfirmDialog)
        _SettingsConfirmDialog(
          title: '修改每日文章数量',
          message: '当前：${state.dailyCount}篇 → 调整至：'
              '${state.pendingCount ?? state.dailyCount}篇\n\n'
              '此设置将在明天生效，今天的学习不受影响。',
          confirmLabel: '确认修改',
          onConfirm: controller.confirmCountChange,
          onDismiss: controller.cancelCountChange,
        ),
    ];
  }
}

/// 内联下划线 tabs（对照 Kotlin SettingsScreen 顶部 TabRow）。
class _InlineTabs extends StatelessWidget {
  const _InlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppPage.horizontalPadding),
      child: Row(
        children: [
          for (final (index, label) in tabs.indexed) ...[
            Expanded(
              child: InkWell(
                onTap: () => onSelect(index),
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: AppType.textTheme.titleMedium?.copyWith(
                          color: index == selectedIndex
                              ? AppColors.primary
                              : AppColors.mutedSoft,
                          fontWeight: index == selectedIndex
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Container(
                        height: 2,
                        color: index == selectedIndex
                            ? AppColors.primary
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 学习设置 tab 内容：5 个设置项（picker / stepper / toggle）。
class _LearningSettingsContent extends StatelessWidget {
  const _LearningSettingsContent({
    required this.state,
    required this.controller,
    required this.onShowLevelPicker,
    required this.onShowTranslationModePicker,
  });

  final SettingsUiState state;
  final SettingsController controller;
  final VoidCallback onShowLevelPicker;
  final VoidCallback onShowTranslationModePicker;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 英文水平
        Row(
          children: [
            Expanded(
              child: _SettingsPickerItem(
                label: '英文水平',
                description: _levelDescription(state.level),
                value: _levelLabel(state.level),
                onClick: onShowLevelPicker,
              ),
            ),
            _InfoTipButton(onClick: controller.showLevelInfo),
          ],
        ),
        // 每日文章数量
        Row(
          children: [
            Expanded(
              child: _SettingsStepperItem(
                label: '每日文章数量',
                description: '从CURRENT batch中展示的文章数，最多5篇',
                value: state.dailyCount,
                canDecrement: state.dailyCount > 1,
                canIncrement: state.dailyCount < 5,
                onDecrement: () =>
                    controller.requestCountChange(state.dailyCount - 1),
                onIncrement: () =>
                    controller.requestCountChange(state.dailyCount + 1),
              ),
            ),
            _InfoTipButton(onClick: controller.showCountInfo),
          ],
        ),
        // 译文默认模式
        _SettingsPickerItem(
          label: '译文默认模式',
          description: '文章阅读时译文显示方式',
          value: _translationModeLabel(state.translationMode),
          onClick: onShowTranslationModePicker,
        ),
        // 单词掌握阈值
        _SettingsStepperItem(
          label: '单词掌握阈值',
          description: '标记认识 N 次后自动移除',
          value: state.masteryThreshold,
          canDecrement: state.masteryThreshold > 1,
          canIncrement: state.masteryThreshold < 5,
          onDecrement: controller.decrementMasteryThreshold,
          onIncrement: controller.incrementMasteryThreshold,
        ),
        // 自动朗读
        _SettingsToggleItem(
          label: '自动朗读',
          description: '进入文章后自动播放朗读',
          checked: state.autoPlayAudio,
          onToggle: controller.toggleAutoPlayAudio,
        ),
      ],
    );
  }
}

/// 学习统计 tab 内容：2×2 StatCard。
class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats});

  final SettingsStatsData stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                stat: StatCardData(
                  number: stats.totalArticlesRead.toString(),
                  label: '阅读文章',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: StatCard(
                stat: StatCardData(
                  number: stats.totalWordsAdded.toString(),
                  label: '添加单词',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: StatCard(
                stat: StatCardData(
                  number: stats.totalLearningDays.toString(),
                  label: '累计学习天数',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: StatCard(
                stat: StatCardData(
                  number: stats.currentStreak.toString(),
                  label: '当前连续学习',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 选择器条目：标签 + 描述 + 当前值 + 右箭头（点击打开选择器弹窗）。
class _SettingsPickerItem extends StatelessWidget {
  const _SettingsPickerItem({
    required this.label,
    required this.description,
    required this.value,
    required this.onClick,
  });

  final String label;
  final String description;
  final String value;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppType.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppType.textTheme.bodySmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: AppType.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.mutedSoft,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 数值 stepper 条目：标签 + 描述 + − value +（44dp 圆角按钮）。
class _SettingsStepperItem extends StatelessWidget {
  const _SettingsStepperItem({
    required this.label,
    required this.description,
    required this.value,
    required this.canDecrement,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final String description;
  final int value;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppType.textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepperButton(
                label: '−',
                enabled: canDecrement,
                onTap: onDecrement,
              ),
              SizedBox(
                width: AppSpacing.lg,
                child: Text(
                  value.toString(),
                  textAlign: TextAlign.center,
                  style: AppType.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _StepperButton(
                label: '+',
                enabled: canIncrement,
                onTap: onIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// stepper 的 44dp 圆角按钮（禁用时 SurfaceSoft 30% 底 + 30% 文字）。
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabledColor = AppColors.surfaceCard;
    final disabledColor = AppColors.surfaceSoft.withValues(alpha: 0.3);
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? enabledColor : disabledColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppType.textTheme.titleMedium?.copyWith(
            color: enabled
                ? AppColors.ink
                : AppColors.mutedSoft.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

/// 开关条目：标签 + 描述 + Switch（选中 Primary 轨道）。
class _SettingsToggleItem extends StatelessWidget {
  const _SettingsToggleItem({
    required this.label,
    required this.description,
    required this.checked,
    required this.onToggle,
  });

  final String label;
  final String description;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppType.textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: checked,
            onChanged: (_) => onToggle(),
            activeThumbColor: AppColors.onPrimary,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: AppColors.ink,
            inactiveTrackColor: AppColors.surfaceSoft,
          ),
        ],
      ),
    );
  }
}

/// ℹ️ 信息按钮（对照 Kotlin InfoTipButton）。
class _InfoTipButton extends StatelessWidget {
  const _InfoTipButton({required this.onClick});

  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClick,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.xs),
        child: Text(
          'ℹ',
          style: TextStyle(fontSize: 14, color: AppColors.mutedSoft),
        ),
      ),
    );
  }
}

/// 选择器弹窗（radio 列表，点击即选，对照 Kotlin SettingsPickerDialog）。
class _SettingsPickerDialog extends StatelessWidget {
  const _SettingsPickerDialog({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelect,
    required this.onDismiss,
  });

  final String title;
  final List<(String, String)> options;
  final String selectedValue;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppModal(
      visible: true,
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppType.textTheme.headlineMedium
                ?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (value, label) in options)
            InkWell(
              onTap: () => onSelect(value),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      selectedValue == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selectedValue == value
                          ? AppColors.primary
                          : AppColors.mutedSoft,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(label, style: AppType.textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ℹ️ 信息弹窗（对照 Kotlin SettingsInfoDialog）。
class _SettingsInfoDialog extends StatelessWidget {
  const _SettingsInfoDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AppModal(
      visible: true,
      onDismiss: onConfirm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppType.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppType.textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: onConfirm,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                child: Text(
                  '知道了',
                  style: AppType.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 确认修改弹窗（对照 Kotlin SettingsConfirmDialog）。
class _SettingsConfirmDialog extends StatelessWidget {
  const _SettingsConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppModal(
      visible: true,
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppType.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppType.textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                  child: Text(
                    '取消',
                    style: AppType.textTheme.labelLarge
                        ?.copyWith(color: AppColors.muted),
                  ),
                ),
              ),
              InkWell(
                onTap: onConfirm,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                  child: Text(
                    confirmLabel,
                    style: AppType.textTheme.labelLarge
                        ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _levelLabel(String level) => switch (level) {
      'LOW' => '初级',
      'MEDIUM' => '中级',
      'HIGH' => '高级',
      _ => level,
    };

String _levelDescription(String level) => switch (level) {
      'LOW' => '初级 · LOW',
      'MEDIUM' => '中级 · MEDIUM',
      'HIGH' => '高级 · HIGH',
      _ => level,
    };

String _translationModeLabel(String mode) => switch (mode) {
      'FULL' => '完全显示',
      'DIM' => '淡化',
      'BLURRED' => '模糊',
      'HIDDEN' => '隐藏',
      _ => mode,
    };
