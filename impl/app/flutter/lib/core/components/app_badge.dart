import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';

enum AppBadgeVariant { default_, coral, green }

/// 小胶囊徽标：难度标签、计数。对照 Kotlin ui/components/AppBadge.kt。
class AppBadge extends StatelessWidget {
  const AppBadge(
    this.text, {
    super.key,
    this.variant = AppBadgeVariant.default_,
  });

  final String text;
  final AppBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (variant) {
      AppBadgeVariant.coral => (AppColors.primary, AppColors.onPrimary),
      AppBadgeVariant.green => (AppColors.success, AppColors.onPrimary),
      AppBadgeVariant.default_ => (AppColors.surfaceSoft, AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppType.textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}
