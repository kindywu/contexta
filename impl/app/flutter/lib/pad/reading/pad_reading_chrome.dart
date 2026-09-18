import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../ui/reading/translation_visibility.dart';
import '../pad_layout.dart';
import 'pad_spread_reader.dart' show rightPageNumberOf;

/// 沉浸式阅读器底部**唯一常驻**的控件：页码胶囊 `12 / 345`。
///
/// 它同时解决三件事，所以值得常驻：
/// 1. **你在哪**——总页数与当前位置，不用唤出控件就能看到；
/// 2. **可以点**——是"上下栏能唤出"的发现性入口（否则用户永远不知道有顶栏）；
/// 3. **不打扰**——一行小字加一个浅底胶囊，比常驻工具栏安静得多。
///
/// 朗读进行中时左侧长出一个极小的暂停键：沉浸态下也必须能停下来。
class PadPagePill extends StatelessWidget {
  const PadPagePill({
    super.key,
    required this.pageController,
    required this.totalPages,
    required this.isSpeaking,
    required this.onToggleChrome,
    required this.onTogglePlayback,
  });

  final PageController pageController;
  final int totalPages;
  final bool isSpeaking;
  final VoidCallback onToggleChrome;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    // 只重建这一行：整屏 setState 会让书页里每个单词的 TapGestureRecognizer
    // 在翻页动画的每一帧重建一次。
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        final spread = pageController.hasClients
            ? (pageController.page ?? 0)
            : 0.0;
        final right = rightPageNumberOf(spread, totalPages);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSpeaking) ...[
              _PillIconButton(
                icon: Icons.pause,
                tooltip: '暂停朗读',
                onTap: onTogglePlayback,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Material(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                onTap: onToggleChrome,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$right / $totalPages',
                        style: AppType.textTheme.labelMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Icon(
                        Icons.keyboard_arrow_up,
                        size: 16,
                        color: AppColors.mutedSoft,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSoft,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: AppColors.bodyText),
          ),
        ),
      ),
    );
  }
}

/// 沉浸态唤出后的顶栏：返回 + 文章标题 + 已读标记 + 译文模式。
///
/// 平板横向空间充裕，标题直接放顶栏（手机上标题在正文流里）。
class PadReadingTopBar extends StatelessWidget {
  const PadReadingTopBar({
    super.key,
    required this.title,
    required this.translationMode,
    required this.isReadCompleted,
    required this.onBack,
    required this.onCycleTranslationMode,
  });

  final String title;
  final TranslationMode translationMode;
  final bool isReadCompleted;
  final VoidCallback onBack;
  final VoidCallback onCycleTranslationMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PadLayout.chromeTopBarHeight,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            color: AppColors.mutedSoft,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
              ),
            ),
          ),
          if (isReadCompleted) ...[
            Text(
              '✓ 已读',
              style: AppType.textTheme.labelMedium?.copyWith(
                color: AppColors.mutedSoft,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          _TranslationChip(
            mode: translationMode,
            onTap: onCycleTranslationMode,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _TranslationChip extends StatelessWidget {
  const _TranslationChip({required this.mode, required this.onTap});

  final TranslationMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Text(
              '译文',
              style: AppType.textTheme.labelMedium?.copyWith(
                color: AppColors.mutedSoft,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              mode.label,
              style: AppType.textTheme.labelMedium?.copyWith(
                color: AppColors.bodyText,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '▾',
              style: AppType.textTheme.labelSmall?.copyWith(
                color: AppColors.mutedSoft,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 沉浸态唤出后的底栏：进度条 + 页码 + 朗读 + 语速。
class PadReadingBottomBar extends StatelessWidget {
  const PadReadingBottomBar({
    super.key,
    required this.progress,
    required this.pageLabel,
    required this.isSpeaking,
    required this.ttsSpeed,
    required this.speechProgress,
    required this.speechTotalSentences,
    required this.onTogglePlayback,
    required this.onToggleTtsSpeed,
    required this.onCollapse,
  });

  /// 0..1，已翻过的页占比。
  final double progress;
  final String pageLabel;
  final bool isSpeaking;
  final double ttsSpeed;
  final double? speechProgress;
  final int? speechTotalSentences;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleTtsSpeed;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    return Container(
      height: PadLayout.chromeBottomBarHeight,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(
            pageLabel,
            style: AppType.textTheme.labelMedium?.copyWith(
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // 进度条：横向空间在平板底栏上是廉价资源，直接铺开
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: AppColors.hairline,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '$percent%',
            style: AppType.textTheme.labelMedium?.copyWith(
              color: AppColors.mutedSoft,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          if (isSpeaking && speechTotalSentences != null) ...[
            Text(
              '第 ${speechProgress?.round() ?? 0}/${speechTotalSentences!} 句',
              style: AppType.textTheme.labelSmall?.copyWith(
                color: AppColors.mutedSoft,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          _BottomBarButton(
            icon: isSpeaking ? Icons.pause : Icons.play_arrow,
            label: isSpeaking ? '暂停' : '朗读',
            primary: true,
            onTap: onTogglePlayback,
          ),
          const SizedBox(width: AppSpacing.xs),
          _BottomBarButton(
            label: '${ttsSpeed}x',
            onTap: onToggleTtsSpeed,
          ),
          const SizedBox(width: AppSpacing.xs),
          _BottomBarButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: '收起工具栏',
            onTap: onCollapse,
          ),
        ],
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    this.icon,
    this.label,
    this.tooltip,
    this.primary = false,
    required this.onTap,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.onPrimary : AppColors.bodyText;
    final button = Material(
      color: primary ? AppColors.primary : AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 8,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                if (label != null) const SizedBox(width: AppSpacing.xxs),
              ],
              if (label != null)
                Text(
                  label!,
                  style: AppType.textTheme.titleSmall?.copyWith(color: fg),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
