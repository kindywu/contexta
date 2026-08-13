import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/theme/app_theme.dart';
import 'di/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 2026-08-13（计划 B Task 6）：本地生成管道移除，workmanager 初始化保留
  // （后台调度能力 T8 换每日同步任务）；占位 dispatcher 不注册任何任务，
  // 未知任务记日志返回成功（避免后台 isolate 崩溃）。
  Workmanager().initialize(backgroundCallbackDispatcher);
  runApp(const ProviderScope(child: MainApp()));
}

/// workmanager 回调派发器（T8 将在此注册每日同步任务）。
///
/// 必须保持顶层函数 + `@pragma('vm:entry-point')`（后台 isolate 通过
/// entry point 发现它，不能被 tree-shake 掉）。
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[WorkerDispatcher] executeTask taskName=$taskName inputData=$inputData');
    return true;
  });
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Contexta',
      theme: buildAppTheme(),
      // 登录守卫集成在 routerProvider（authServiceProvider 状态变化 →
      // refreshListenable 重估重定向，无需重建 router）
      routerConfig: ref.watch(routerProvider),
    );
  }
}
