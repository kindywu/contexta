import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';

enum AppButtonVariant { primary, secondary }

/// 原型风格按钮：Primary = 珊瑚实心 + OnPrimary 文字；Secondary =
/// SurfaceCard 底 + Ink 文字；禁用 = PrimaryDisabled 40% 底 + Ink 40% 文字。
///
/// 对照 Kotlin ui/components/AppButton.kt（无按压 scale 动画）。
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    required this.onClick,
    this.variant = AppButtonVariant.primary,
    this.enabled = true,
    this.shape,
  });

  final String text;
  final VoidCallback onClick;
  final AppButtonVariant variant;
  final bool enabled;
  final BorderRadius? shape;

  @override
  Widget build(BuildContext context) {
    final (Color container, Color contentColor) = switch (variant) {
      AppButtonVariant.primary => (AppColors.primary, AppColors.onPrimary),
      AppButtonVariant.secondary => (AppColors.surfaceCard, AppColors.ink),
    };
    final effectiveContainer = enabled
        ? container
        : AppColors.primaryDisabled.withValues(alpha: 0.4);
    final effectiveContent = enabled
        ? contentColor
        : AppColors.ink.withValues(alpha: 0.4);

    return Material(
      color: effectiveContainer,
      borderRadius: shape ?? BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: enabled ? onClick : null,
        borderRadius: shape ?? BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Center(
            child: Text(
              text,
              style: AppType.textTheme.titleSmall?.copyWith(
                color: effectiveContent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形图标按钮，默认 44dp 触控目标（正文内辅助发音钮允许 36dp）。
/// 对照 Kotlin ui/components/AppButton.kt 的 AppIconButton。
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onClick,
    this.size = AppPage.minTouchTarget,
    this.tint,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onClick;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final effectiveTint = tint ?? Theme.of(context).colorScheme.onSurface;
    return IconButton(
      onPressed: onClick,
      tooltip: tooltip,
      icon: Icon(icon, size: 24, color: effectiveTint),
      style: IconButton.styleFrom(
        minimumSize: Size.square(size),
        maximumSize: Size.square(size + 4),
      ),
    );
  }
}
