import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';
import '../domain/model/article.dart';
import '../ui/home/home_controller.dart';
import 'pad_article_card.dart' show difficultyAccent;
import 'pad_layout.dart';
import 'pad_providers.dart';

/// 首页 Hero 卡「继续阅读」——**只有横屏才成立的一屏**。
///
/// 手机首页一张卡只有标题（宽度不够）；平板横屏的宽度能同时放下
/// **真实英文开头段 + 元信息 + 入口**，于是"读哪篇"这个决策在首页就能做完，
/// 不必点进去再退出来。这是本次重设计里唯一一处"手机做不到"的信息密度，
/// 也是产品原则「语境优先」在首页的落点：让人先看到真实正文再决定。
class PadContinueCard extends ConsumerWidget {
  const PadContinueCard({
    super.key,
    required this.article,
    required this.onStart,
  });

  /// 推荐阅读的文章（首页状态里的第一篇未读）。
  final ArticleItemUi article;
  final ValueChanged<int> onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = difficultyAccent(article.difficultyLabel);
    // 开头段单独取（首页列表不带段落），失败/加载中只是少一段预览，不阻塞卡片
    final preview = ref
        .watch(padArticleDetailProvider(article.id))
        .maybeWhen(
          data: (a) => _firstParagraph(a),
          orElse: () => null,
        );
    final resumed = article.accumulatedReadSeconds > 0;

    // 左边不缩进：Hero 的左右边距若与下方网格不一致，两张卡片的左边缘就会
    // 差出 32dp（实测反馈的"今日推荐跟下面的文章没有左对齐"）。网格与分组
    // 标题都是贴右栏左沿、只留右边距，Hero 跟随同一套。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        AppSpacing.lg,
        PadLayout.pagePadding,
        AppSpacing.xl,
      ),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(PadLayout.heroRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onStart(article.id),
          child: Padding(
            padding: PadLayout.heroPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resumed ? '继续阅读' : '今日推荐',
                        style: AppType.textTheme.labelSmall?.copyWith(
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        article.title ?? article.categoryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.textTheme.headlineLarge?.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // 真实开头段：卡片的核心价值，读不到正文时不占位
                      Text(
                        preview ?? '打开文章开始今天的阅读',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // 正文预览是卡片里的小字，**不跟**阅读页译文样式
                        // （AppType.readingTranslation 是 17sp 正文级字号）
                        style: AppType.textTheme.bodyMedium!.copyWith(
                          color: AppColors.bodyText,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _HeroMeta(article: article, accent: accent),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                _StartButton(
                  label: resumed ? '继续阅读' : '开始阅读',
                  onTap: () => onStart(article.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 首个非空正文段（标题不在 paragraphs 里）。
  static String? _firstParagraph(Article? article) {
    for (final p in article?.paragraphs ?? const <ArticleParagraph>[]) {
      final text = p.englishText.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}

/// Hero 元信息行：难度徽标 + 分类 + 已读时长。
class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.article, required this.accent});

  final ArticleItemUi article;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final minutes = article.accumulatedReadSeconds ~/ 60;
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
        const SizedBox(width: AppSpacing.sm),
        Text(
          article.categoryLabel,
          style: AppType.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        if (minutes > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            '已读 $minutes 分钟',
            style: AppType.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedSoft,
            ),
          ),
        ],
      ],
    );
  }
}

/// 主行动按钮（珊瑚实心）。不用共享的 `AppButton`——pad 卡内的按钮尺寸与
/// 手机按钮不同，且这条路径必须与手机界面零耦合。
class _StartButton extends StatelessWidget {
  const _StartButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                label,
                style: AppType.textTheme.titleSmall?.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              const Icon(
                Icons.arrow_forward,
                size: 16,
                color: AppColors.onPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
