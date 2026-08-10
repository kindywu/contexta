import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 原型卡片：SurfaceCard 底 + 12dp 圆角 + 16dp 内边距；onClick 非空时整卡可点。
/// 对照 Kotlin ui/components/AppCard.kt。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.onClick,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    required this.child,
  });

  final VoidCallback? onClick;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onClick,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
