import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'data/background/sync_callback_dispatcher.dart';
import 'core/platform/app_orientation.dart';
import 'core/platform/device_form_factor.dart';
import 'core/theme/app_theme.dart';
import 'di/providers.dart';
import 'ui/auth/eviction_notice_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 设备形态（2026-09-18）：启动时**只判定一次**，由此决定全局走哪棵界面树
  // （手机 `lib/ui/` 竖屏 / 平板 `lib/pad/` 横屏），并据此锁定方向。
  // 判定源是物理显示屏而非窗口尺寸——窗口在启动瞬间是 0，且平板被
  // letterbox 时窗口本身就是错的。详见 docs/adaptive-layout.md。
  final formFactor = await resolveStartupFormFactor();
  // 方向策略：手机固定竖屏、平板固定横屏，两者都不允许翻转。
  // 原生侧（AndroidManifest）覆盖引擎启动前的启动窗口（闪屏期）；
  // 此处覆盖引擎启动后的运行期旋转。详见 docs/app-orientation.md。
  await applyOrientationPolicy(formFactor);
  // 自签名 HTTPS 信任锚：预载内嵌证书（Dart TLS 栈不读 Android NSC，必须显式注入，
  // 见 di/providers.dart；失败仅告警，本地开发/无证书场景继续默认信任库）
  await loadServerTrustCert();
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
  runApp(
    ProviderScope(
      // 启动时判定一次的设备形态：整棵界面树的唯一分派依据
      overrides: [formFactorProvider.overrideWithValue(formFactor)],
      child: const MainApp(),
    ),
  );
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
        // 被踢提示（两棵树共用）：监听 authService 的待展示通知
        builder: (context, child) =>
            EvictionNoticeHost(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
