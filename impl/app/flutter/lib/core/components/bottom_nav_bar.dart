import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_type.dart';

/// 底部导航 tab（对照 Kotlin BottomNavTab：Home/Vocabulary/Reference/
/// Settings 四个一级页面；Reading/AddWord/Onboarding 不在底栏）。
enum BottomNavTab {
  home(route: 'home', label: '首页', icon: Icons.home_outlined),
  vocabulary(route: 'vocabulary', label: '生词', icon: Icons.menu_book_outlined),
  reference(route: 'reference', label: '参考', icon: Icons.auto_stories_outlined),
  settings(route: 'settings', label: '设置', icon: Icons.settings_outlined);

  const BottomNavTab({
    required this.route,
    required this.label,
    required this.icon,
  });

  final String route;
  final String label;
  final IconData icon;
}

/// 底部导航栏：顶部 1dp Hairline 分隔线 + 4 tab；选中 = Primary 珊瑚、
/// 未选中 = Muted；标签 titleSmall。对照 Kotlin ui/components/BottomNavBar.kt。
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
  });

  final BottomNavTab selectedTab;
  final ValueChanged<BottomNavTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(
          height: 1,
          thickness: 1,
          color: AppColors.hairline,
        ),
        Material(
          color: AppColors.surfaceCard,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final tab in BottomNavTab.values)
                  _TabItem(
                    tab: tab,
                    selected: tab == selectedTab,
                    onTap: () => onTabSelected(tab),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final BottomNavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 24, color: color),
            Text(
              tab.label,
              style: AppType.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
