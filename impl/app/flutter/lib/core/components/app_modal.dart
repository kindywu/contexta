import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_type.dart';

enum AppModalAlignment { center, bottom }

/// 原型弹窗：全屏 Scrim 遮罩 + 画布底面板（淡入淡出 200ms）。
///
/// - center（默认）：居中卡片，四角 16dp 圆角，宽 ≤ 360dp（参考页弹窗）
/// - bottom：底部全宽弹层，仅上两角 16dp 圆角，高 ≤ 75% 屏高（查词弹窗）
///
/// 面板内部消费点击（无涟漪），防止点击面板空白区穿透触发关闭。
/// 对照 Kotlin ui/components/AppModal.kt（AnimatedVisibility 淡入淡出）。
class AppModal extends StatelessWidget {
  const AppModal({
    super.key,
    required this.visible,
    required this.onDismiss,
    this.alignment = AppModalAlignment.center,
    required this.child,
  });

  final bool visible;
  final VoidCallback onDismiss;
  final AppModalAlignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isBottom = alignment == AppModalAlignment.bottom;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.lg),
      topRight: const Radius.circular(AppRadius.lg),
      bottomLeft:
          isBottom ? Radius.zero : const Radius.circular(AppRadius.lg),
      bottomRight:
          isBottom ? Radius.zero : const Radius.circular(AppRadius.lg),
    );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.base,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: const ColoredBox(color: AppColors.scrim),
              ),
            ),
            // Align（非 Positioned）在 Stack 中填充全屏，面板才能真正居中
            // （对照 Kotlin Box(fillMaxSize) + Column.align）
            Align(
              alignment:
                  isBottom ? Alignment.bottomCenter : Alignment.center,
              child: SizedBox(
                width: isBottom ? double.infinity : null,
                child: ConstrainedBox(
                  constraints: isBottom
                      ? BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height * 0.75,
                        )
                      : const BoxConstraints(maxWidth: 360),
                  child: Material(
                    color: AppColors.background,
                    borderRadius: radius,
                    clipBehavior: Clip.antiAlias,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 原型 toast：深色底 + 画布色文字 + 8dp 圆角。
/// 对照 Kotlin ui/components/AppModal.kt 的 AppToast（预留组件，当前未接线）。
class AppToast extends StatelessWidget {
  const AppToast(
    this.text, {
    super.key,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.toastDark,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: AppType.textTheme.bodyMedium?.copyWith(
          color: AppColors.background,
        ),
      ),
    );
  }
}
