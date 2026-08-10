import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';
import 'app_card.dart';

class StatCardData {
  const StatCardData({
    required this.number,
    required this.label,
    this.sub,
  });

  final String number;
  final String label;
  final String? sub;
}

/// 统计卡片（基于 AppCard）：居中数字 + 标签 + 可选珊瑚小注。
/// 对照 Kotlin ui/components/StatCard.kt。
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.stat,
  });

  final StatCardData stat;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Text(stat.number, style: AppType.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            stat.label,
            style: AppType.textTheme.bodySmall?.copyWith(
              color: AppColors.bodyText,
            ),
          ),
          if (stat.sub != null) ...[
            Text(
              stat.sub!,
              style: AppType.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
