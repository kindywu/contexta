import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/theme/app_theme.dart';
import 'data/background/background_callback_dispatcher.dart';
import 'di/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 注册后台任务回调（Task 18）：后台 isolate 通过该顶层函数执行
  // 批次生成；多次调用是幂等的（平台层只注册一次）
  Workmanager().initialize(backgroundCallbackDispatcher);
  runApp(const ProviderScope(child: MainApp()));
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
