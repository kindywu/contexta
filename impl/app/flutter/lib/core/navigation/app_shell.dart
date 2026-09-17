import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/bottom_nav_bar.dart';
import 'routes.dart';

/// 应用壳（对照 Kotlin MainActivity.ContextaApp）：
/// - 一级页面（home/reference/settings）显示底栏；vocabulary 在 Kotlin 中
///   也不在底栏列表（BottomNavTab 覆盖 home/vocabulary/reference/settings，
///   但 showBottomBar 列表缺 vocabulary —— 保持对齐）
/// - 选中 tab 由当前路由推导；切换 = context.go（等价 launchSingleTop，
///   且不会重复压栈）
/// - Reading/AddWord/Onboarding 全屏，无底栏
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
    final showBottomBar = _bottomBarRoutes.contains(location);
    final currentTab = BottomNavTab.values
        .where((t) => Routes.location(t.route) == location)
        .firstOrNull;

    return Scaffold(
      // SafeArea：灵动岛（挖孔）/手势条区域留安全边距（对照 Kotlin
      // enableEdgeToEdge + Scaffold 默认消费 systemBars insets）
      body: SafeArea(child: child),
      bottomNavigationBar: showBottomBar && currentTab != null
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
