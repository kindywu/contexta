import 'package:flutter/widgets.dart';

/// 窗口宽度档位（对照 Material 3 大屏断点）：
/// compact < 600 ≤ medium < 840 ≤ expanded。
///
/// 用**窗口宽度**而非「设备类型」判定：与 Android 16 大屏忽略方向声明
/// 的阈值（sw600dp）同源，且自动覆盖分屏 / 折叠屏。
enum WindowSize { compact, medium, expanded }

/// medium 档下界（也就是 Android 的 sw600dp 大屏线）。
const double kMediumWidthBreakpoint = 600;

/// expanded 档下界：书页模式（左右两屏）的启用宽度。
const double kExpandedWidthBreakpoint = 840;

WindowSize windowSizeFor(double width) {
  if (width < kMediumWidthBreakpoint) return WindowSize.compact;
  if (width < kExpandedWidthBreakpoint) return WindowSize.medium;
  return WindowSize.expanded;
}

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => windowSizeFor(MediaQuery.sizeOf(this).width);

  /// 书页模式 / 内容多栏的启用条件。
  bool get isExpandedLayout => windowSize == WindowSize.expanded;

  /// 导航骨架：true = 左侧 NavigationRail，false = 底部导航栏（手机）。
  bool get usesNavRail => windowSize != WindowSize.compact;
}
