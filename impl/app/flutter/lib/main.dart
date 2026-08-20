import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'data/background/sync_callback_dispatcher.dart';
import 'core/theme/app_theme.dart';
import 'di/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 2026-08-14（计划 B Task 8）：workmanager 换每日同步任务——
  // 定时拉取服务端已审核文章（幂等 upsert）。首次任务延迟 2h
  // （启动编排已同步过，无需刚启动即重复）；之后每 24h 一次；
  // 网络断开时任务跳过，等下一次周期窗口。
  Workmanager().initialize(syncCallbackDispatcher);
  Workmanager().registerPeriodicTask(
    dailySyncTaskName,
    dailySyncTaskName,
    frequency: const Duration(hours: 24),
    constraints: Constraints(networkType: NetworkType.connected),
    initialDelay: const Duration(hours: 2),
  );
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 数据库就绪门禁（2026-08-14 真机红屏修复）：databaseProvider 是
    // FutureProvider，而 routerProvider → authServiceProvider →
    // settingsRepositoryProvider 等 8 处直接 `requireValue`——DB 未加载完
    // 就构建路由树会抛 StateError（AsyncLoading<AppDatabase> 竞态，时好时坏）。
    // 门禁保证整棵树只在 DB 就绪后构建，8 处 requireValue 全部安全。
    final db = ref.watch(databaseProvider);
    return db.when(
      loading: () => const MaterialApp(
        title: 'Contexta',
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        title: 'Contexta',
        home: Scaffold(
          body: Center(child: Text('数据库初始化失败：$e')),
        ),
      ),
      data: (_) => MaterialApp.router(
        title: 'Contexta',
        theme: buildAppTheme(),
        // 登录守卫集成在 routerProvider（authServiceProvider 状态变化 →
        // refreshListenable 重估重定向，无需重建 router）
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}
