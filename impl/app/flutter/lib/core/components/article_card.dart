import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';
import 'app_badge.dart';
import 'app_card.dart';

class ArticleCardData {
  const ArticleCardData({
    required this.id,
    required this.title,
    required this.description,
    required this.difficultyLabel,
    required this.categoryLabel,
    this.isReadCompleted = false,
  });

  final int id;
  final String? title;
  final String description;
  final String difficultyLabel;
  final String categoryLabel;
  final bool isReadCompleted;
}

/// 文章卡片（基于 AppCard）：serif 标题单行省略 + Muted 描述两行省略 +
/// 难度徽标（CET4 → Coral、CET6 → Green、其他 → Default）+ 分类 + 已读标记。
/// 对照 Kotlin ui/components/ArticleCard.kt。
class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.article,
    required this.onClick,
  });

  final ArticleCardData article;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onClick: onClick,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title ?? (article.description.length > 40
                ? article.description.substring(0, 40)
                : article.description),
            style: AppType.textTheme.headlineMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            article.description,
            style: AppType.textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              AppBadge(
                article.difficultyLabel,
                variant: switch (article.difficultyLabel) {
                  'CET4' => AppBadgeVariant.coral,
                  'CET6' => AppBadgeVariant.green,
                  _ => AppBadgeVariant.default_,
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                article.categoryLabel,
                style: AppType.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              if (article.isReadCompleted) ...[
                const Spacer(),
                Text(
                  '✓ 已读',
                  style: AppType.textTheme.labelSmall?.copyWith(
                    color: AppColors.mutedSoft,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
