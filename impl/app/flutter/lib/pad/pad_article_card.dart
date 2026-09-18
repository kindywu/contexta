import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';
import 'pad_layout.dart';

/// Pad 文章卡的数据（`lib/pad/` 自有类型，不复用手机侧的 `ArticleCardData`）。
class PadArticleCardData {
  const PadArticleCardData({
    required this.id,
    required this.title,
    required this.difficultyLabel,
    required this.categoryLabel,
    this.isReadCompleted = false,
  });

  final int id;
  final String? title;
  final String difficultyLabel;
  final String categoryLabel;
  final bool isReadCompleted;
}

/// Pad 文章卡——**封面式**，平板专属实现（与手机 `ArticleCard` 无共享代码）。
///
/// 手机卡是一条抬头看标题的文字行；平板上铺成网格后，纯文字卡片会变成
/// "一片灰"，扫视时没有落点。这里给每张卡一个**类型化封面块**（按难度取色
/// 的整块 + 分类名），承担微信读书里书封的角色：给网格视觉节奏，让眼睛能
/// 按色块快速定位，而不是逐行读标题。
///
/// 封面块不是装饰——它的颜色编码难度（CET4 青 / CET6 珊瑚 / 专八 琥珀），
/// 与卡内难度徽标同色，两处互相印证。
class PadArticleCard extends StatelessWidget {
  const PadArticleCard({
    super.key,
    required this.article,
    required this.onClick,
  });

  final PadArticleCardData article;
  final VoidCallback onClick;

  /// 标题缺失时回落到分类名（与手机卡同一降级规则：不能出现空标题卡）。
  String get _displayTitle {
    final String? title = article.title;
    if (title != null && title.isNotEmpty) return title;
    return article.categoryLabel;
  }

  @override
  Widget build(BuildContext context) {
    final accent = difficultyAccent(article.difficultyLabel);
    final read = article.isReadCompleted;

    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onClick,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PadCover(
              accent: accent,
              categoryLabel: article.categoryLabel,
              // 已读的封面褪色：网格里一眼能分出"哪些读过了"
              dimmed: read,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayTitle,
                      style: AppType.textTheme.headlineMedium?.copyWith(
                        color: read ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    const Spacer(),
                    _MetaRow(article: article, accent: accent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面块：难度色调的整块 + 分类名（衬线，贴底左对齐——像书脊上的分类条）。
///
/// 公开而非私有：网格测试要断言「每行封面等高」「已读褪色」，
/// 需要按类型定位到它。
class PadCover extends StatelessWidget {
  const PadCover({
    super.key,
    required this.accent,
    required this.categoryLabel,
    required this.dimmed,
  });

  final Color accent;
  final String categoryLabel;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PadLayout.cardCoverHeight,
      // 低透明度叠色：整块高饱和会让 12 张卡变成调色盘，14% 只留一层色调
      color: accent.withValues(alpha: dimmed ? 0.06 : 0.14),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          categoryLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.textTheme.headlineSmall?.copyWith(
            fontFamily: 'serif',
            color: dimmed ? AppColors.mutedSoft : AppColors.bodyText,
            height: 22 / 16,
          ),
        ),
      ),
    );
  }
}

/// 难度徽标 + 已读标记。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.article, required this.accent});

  final PadArticleCardData article;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            article.difficultyLabel,
            style: AppType.textTheme.labelMedium?.copyWith(
              color: AppColors.onPrimary,
            ),
          ),
        ),
        const Spacer(),
        if (article.isReadCompleted)
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 14,
                color: AppColors.mutedSoft,
              ),
              const SizedBox(width: 3),
              Text(
                '已读',
                style: AppType.textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedSoft,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 难度 → 强调色（封面块与徽标共用，保证同一张卡内两处同色）。
Color difficultyAccent(String label) => switch (label) {
  'CET4' => AppColors.teal,
  'CET6' => AppColors.primary,
  '专八' => AppColors.amber,
  _ => AppColors.mutedSoft,
};
