import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';

/// 居中加载指示：32dp 珊瑚 spinner + 文案。
/// 对照 Kotlin ui/components/LoadingIndicator.kt。
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.message = '加载中…',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: AppType.textTheme.bodyMedium?.copyWith(
            color: AppColors.bodyText,
          ),
        ),
      ],
    );
  }
}

/// 空状态：48dp outline 图标 + 标题 + 可选副文案。
/// 对照 Kotlin ui/components/LoadingIndicator.kt 的 EmptyState。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.message = '暂无内容',
    this.subMessage = '',
  });

  final IconData icon;
  final String message;
  final String subMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: AppColors.hairline),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: AppType.textTheme.titleMedium?.copyWith(
            color: AppColors.bodyText,
          ),
        ),
        if (subMessage.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subMessage,
            style: AppType.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoft,
            ),
          ),
        ],
      ],
    );
  }
}
