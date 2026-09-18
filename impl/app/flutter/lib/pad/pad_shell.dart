import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/components/bottom_nav_bar.dart';
import '../core/navigation/routes.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';
import 'pad_layout.dart';

/// 平板导航骨架：**左侧常驻侧边栏 + 右侧内容区**。
///
/// 与手机骨架（[AppShell]，底部导航栏）并列的另一棵树，由启动时判定一次的
/// 设备形态二选一（见 `core/navigation/app_router.dart`），互不影响。
///
/// **为什么不是 `NavigationRail`**：`NavigationRail` 是"把底栏竖过来"的组件
/// ——窄、图标在上文字在下、没有分组。平板横屏真正的范式是**侧边栏**（微信
/// 读书、Gmail、系统设置）：更宽、图标 + 文字横排、顶部有字标、条目是整行
/// 可点区域。这里按后者自绘。
class PadSidebar extends StatelessWidget {
  const PadSidebar({
    super.key,
    required this.currentTab,
    required this.onSelect,
  });

  final BottomNavTab currentTab;
  final ValueChanged<BottomNavTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PadLayout.sidebarWidth,
      color: AppColors.surfaceSoft,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 字标：平板横屏的侧边栏顶部应该有身份，而不是直接开始列条目
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                'Contexta',
                style: AppType.textTheme.headlineLarge?.copyWith(
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final tab in BottomNavTab.values)
              _SidebarItem(
                tab: tab,
                selected: tab == currentTab,
                onTap: () => onSelect(tab),
              ),
            const Spacer(),
            // 底部说明：横屏侧边栏底部留白很大，放一句产品定位比空着好
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                '在真实语境里\n习得词汇',
                style: AppType.textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedSoft,
                  height: 18 / 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 侧边栏条目：整行可点，选中态用左侧珊瑚竖条 + 表面色块标记。
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final BottomNavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.ink : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: selected ? AppColors.surfaceCard : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                // 选中竖条：颜色之外的第二个信号（色觉障碍下仍可辨）
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(tab.icon, size: 20, color: fg),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  tab.label,
                  style: AppType.textTheme.titleSmall?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 平板导航骨架：侧边栏 + 内容区。
///
/// 只在一级页面（首页 / 生词 / 参考 / 设置）显示侧边栏；阅读页等全屏页面
/// 不套侧边栏，内容直接铺满。
class PadShell extends StatelessWidget {
  const PadShell({super.key, required this.child});

  final Widget child;

  /// 显示侧边栏的页面（与手机骨架保持同一份语义）。
  static const _navRoutes = {
    Routes.home,
    Routes.reference,
    Routes.settings,
  };

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final showNav = _navRoutes.contains(location);
    final currentTab = BottomNavTab.values
        .where((t) => Routes.location(t.route) == location)
        .firstOrNull;

    if (!showNav || currentTab == null) {
      return Scaffold(body: SafeArea(child: child));
    }

    return Scaffold(
      body: Row(
        children: [
          PadSidebar(
            currentTab: currentTab,
            onSelect: (tab) => context.go(tab.route),
          ),
          Expanded(child: SafeArea(left: false, child: child)),
        ],
      ),
    );
  }
}
