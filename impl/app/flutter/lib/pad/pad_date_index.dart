import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';
import '../ui/home/home_controller.dart';
import 'pad_layout.dart';

/// 首页左栏「日期索引」——把竖屏里滚动经过的日期分组标题，变成一列常驻目录。
///
/// **这是横屏才成立的结构**：手机上日期只能作为分组标题夹在卡片流里，读到
/// 哪儿才知道有哪几天；横屏有宽度把它抽成独立一列，一眼看全所有日期与各自
/// 进度，点选即筛选右侧网格。"滚动找日期"由此变成"索引选日期"。
class PadDateIndex extends StatelessWidget {
  const PadDateIndex({
    super.key,
    required this.groups,
    required this.selectedDate,
    required this.onSelect,
  });

  final List<ArticleGroupUi> groups;
  final String? selectedDate;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PadLayout.dateIndexWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              '阅读记录',
              style: AppType.textTheme.labelSmall?.copyWith(
                color: AppColors.mutedSoft,
              ),
            ),
          ),
          for (final group in groups)
            _DateRow(
              label: group.dateLabel,
              read: group.articles.where((a) => a.isReadCompleted).length,
              total: group.articles.length,
              selected: group.dateLabel == selectedDate,
              onTap: () => onSelect(group.dateLabel),
            ),
        ],
      ),
    );
  }
}

/// 一行日期：日期 + `3/5` 进度。整行可点，选中态用表面色块 + 珊瑚竖条。
class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.read,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int read;
  final int total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.surfaceCard : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 10,
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.textTheme.titleSmall?.copyWith(
                      color: selected ? AppColors.ink : AppColors.bodyText,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                // 进度：读完的日期显示为整行都是 muted，未读完的用珊瑚强调
                Text(
                  '$read/$total',
                  style: AppType.textTheme.labelMedium?.copyWith(
                    color: read == total && total > 0
                        ? AppColors.mutedSoft
                        : AppColors.primary,
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
