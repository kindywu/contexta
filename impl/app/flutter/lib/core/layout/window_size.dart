import 'package:flutter/widgets.dart';

/// 窗口尺寸工具：**两棵界面树之间唯一的分叉点**。
///
/// 本项目不做「同一界面内的宽度适配」——手机界面（`lib/ui/`）与 pad 界面
/// （`lib/pad/`）是并列的两棵树，各自按自己的形态设计，互不影响。路由按
/// [WindowSizeContext.isPadLayout] 二选一。
///
/// 档位常量仍按 Material 3 大屏断点，供 pad 界面内部做更细的分栏决策使用。
enum WindowSize { compact, medium, expanded }

/// medium 档下界（也是 Android 的 sw600dp 大屏线，pad 界面的启用阈值）。
const double kMediumWidthBreakpoint = 600;

/// expanded 档下界（pad 界面内部：从「两栏」升级到「多栏」的参考宽度）。
const double kExpandedWidthBreakpoint = 840;

WindowSize windowSizeFor(double width) {
  if (width < kMediumWidthBreakpoint) return WindowSize.compact;
  if (width < kExpandedWidthBreakpoint) return WindowSize.medium;
  return WindowSize.expanded;
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => windowSizeFor(MediaQuery.sizeOf(this).width);

  /// **界面树选择**：true = pad 界面树，false = 手机界面树。
  ///
  /// 按**最短边**判定而非宽度：横竖屏都算 pad；被分屏压窄到 600dp 以下时
  /// 回落手机界面。与 Android 的 sw600dp 大屏线同源，也与系统「这台设备算
  /// 不算平板」的判断一致。
  bool get isPadLayout =>
      MediaQuery.sizeOf(this).shortestSide >= kMediumWidthBreakpoint;
}
