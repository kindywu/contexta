import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/background/background_callback_dispatcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 注册后台任务回调（Task 18）：后台 isolate 通过该顶层函数执行
  // 批次生成；多次调用是幂等的（平台层只注册一次）
  Workmanager().initialize(backgroundCallbackDispatcher);
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Contexta',
      theme: buildAppTheme(),
      routerConfig: buildRouter(),
    );
  }
}
