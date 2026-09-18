import 'dart:async';
import 'dart:ui' show Display, FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设备形态：**手机 / 平板两棵树的分派依据**。
///
/// 在 `main()` 里 **一次性** 解析，随后经 [formFactorProvider] 注入整棵树。
/// 不在界面里按窗口宽度反复推断——方向是锁死的（手机竖屏 / 平板横屏），
/// 窗口尺寸不会变，"启动时判定一次"既够用又避免了每帧重算。
enum DeviceFormFactor { phone, pad }

/// 平板判定线：最短边 ≥ 600dp（Android 的 `sw600dp` 大屏线，与
/// `core/layout/window_size.dart` 的 [kMediumWidthBreakpoint] 同源）。
///
/// 按**最短边**而非宽度：横竖屏都算平板，与系统「这台设备算不算平板」
/// 的判断一致。
const double kPadShortestSideThreshold = 600;

/// 纯函数：由**显示屏**的物理尺寸与像素比判定形态。
///
/// 判定源必须是显示屏本身，不能用窗口尺寸——窗口在启动瞬间可能是 0，
/// 且平板被 letterbox 时窗口本身就已经是错的（实测平板被塞进 600×800dp
/// 竖条，按窗口判会得出"手机"）。
DeviceFormFactor formFactorForDisplay({
  required Size physicalSize,
  required double devicePixelRatio,
}) {
  if (physicalSize.isEmpty || devicePixelRatio <= 0) {
    return DeviceFormFactor.phone;
  }
  final logical = physicalSize / devicePixelRatio;
  return logical.shortestSide >= kPadShortestSideThreshold
      ? DeviceFormFactor.pad
      : DeviceFormFactor.phone;
}

/// 解析启动形态。**必须在 `runApp` 之前 await**。
///
/// 显示屏尺寸理论上在引擎启动后即可读，但首帧之前引擎可能还没推来显示
/// 指标（实测该竞态真实存在：拿到的 `physicalSize` 是 0）。此时轮询等待，
/// 上限 [timeout]，超时按手机处理。
///
/// **为什么超时兜底选手机**：误判成平板会让手机锁横屏（整机不可用），
/// 误判成手机只是让平板晚一帧进横屏（可恢复）。两害相权取轻。
Future<DeviceFormFactor> resolveStartupFormFactor({
  Duration timeout = const Duration(seconds: 2),
}) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final display = await _awaitDisplaySize(view, timeout);
  final factor = formFactorForDisplay(
    physicalSize: display.size,
    devicePixelRatio: display.devicePixelRatio,
  );
  if (kDebugMode) {
    final logical = display.size / display.devicePixelRatio;
    debugPrint(
      '[form-factor] display=${display.size} dpr=${display.devicePixelRatio} '
      'logical=$logical shortest=${logical.shortestSide} → $factor',
    );
  }
  return factor;
}

/// 等到 [FlutterView.display] 报出非零尺寸（或超时）。
///
/// 轮询而非监听 `onMetricsChanged`：这段代码跑在 `runApp` 之前，一帧都还
/// 没画，16ms 的轮询开销可以忽略；而用回调需要临时接管平台的 metrics
/// 回调再还回去，反而容易和其它监听者打架。
Future<Display> _awaitDisplaySize(FlutterView view, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (view.display.size.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  return view.display;
}

/// 启动形态 Provider。**值由 `main()` 覆写注入**（见 `main.dart`）。
///
/// 不给默认值：忘了注入应当在启动时立刻炸掉，而不是悄悄按某个形态跑起来
/// ——静默的默认值正是"平板跑成手机界面"这类问题最难查的地方。
/// 测试里用 `ProviderScope(overrides: [formFactorProvider.overrideWithValue(...)])`。
final formFactorProvider = Provider<DeviceFormFactor>(
  (ref) => throw StateError(
    'formFactorProvider 未注入：请在 ProviderScope.overrides 里用 '
    'main() 解析出的 DeviceFormFactor 覆写它。',
  ),
);
