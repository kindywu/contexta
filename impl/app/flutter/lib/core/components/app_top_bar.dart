import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';
import 'app_button.dart';

/// 统一顶栏：44dp 返回钮（MutedSoft）+ serif 标题 + 右侧 actions 槽位。
/// 对照 Kotlin ui/components/AppTopBar.kt。
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            AppIconButton(
              icon: Icons.arrow_back,
              tooltip: '返回',
              onClick: onBack!,
              tint: AppColors.mutedSoft,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Expanded(
            child: Text(
              title,
              style: AppType.textTheme.displayMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 全大写分组标签：12sp/500/+1.5sp 字距。
/// 对照 Kotlin ui/components/AppTopBar.kt 的 SectionLabel。
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.title, {
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(
        title.toUpperCase(),
        style: AppType.textTheme.labelSmall?.copyWith(
          color: AppColors.mutedSoft,
        ),
      ),
    );
  }
}
