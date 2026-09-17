import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/bottom_nav_bar.dart';
import '../layout/window_size.dart';
import 'routes.dart';

/// 应用壳（对照 Kotlin MainActivity.ContextaApp）：
/// - 一级页面（home/reference/settings）显示导航骨架；vocabulary 在 Kotlin
///   中也不在底栏列表（BottomNavTab 覆盖 home/vocabulary/reference/settings，
///   但 showBottomBar 列表缺 vocabulary —— 保持对齐）
/// - 导航形态随窗口宽度档位切换（`context.usesNavRail`）：手机（compact）
///   底部导航栏，pad / 大屏（medium + expanded）左侧 NavigationRail；
///   两者共用同一份 BottomNavTab 与「当前路由推导选中 tab」逻辑
/// - 选中 tab 由当前路由推导；切换 = context.go（等价 launchSingleTop，
///   且不会重复压栈）
/// - Reading/AddWord/Onboarding 全屏，无导航骨架
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _bottomBarRoutes = {
    Routes.home,
    Routes.reference,
    Routes.settings,
  };

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final showNav = _bottomBarRoutes.contains(location);
    final currentTab = BottomNavTab.values
        .where((t) => Routes.location(t.route) == location)
        .firstOrNull;

    // 大屏（≥600dp，含 pad 横竖屏）用左侧导航栏；手机保持底部导航栏不变。
    if (showNav && currentTab != null && context.usesNavRail) {
      return Scaffold(
        // SafeArea：灵动岛（挖孔）/手势条区域留安全边距（对照 Kotlin
        // enableEdgeToEdge + Scaffold 默认消费 systemBars insets）
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: currentTab.index,
                onDestinationSelected: (index) =>
                    context.go(BottomNavTab.values[index].route),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final tab in BottomNavTab.values)
                    NavigationRailDestination(
                      icon: Icon(tab.icon),
                      label: Text(tab.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: showNav && currentTab != null
          ? BottomNavBar(
              selectedTab: currentTab,
              onTabSelected: (tab) {
                context.go(tab.route);
              },
            )
          : null,
    );
  }
}
