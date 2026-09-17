import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../layout/window_size.dart';

/// 方向策略（2026-09-17 起分手机 / 平板两档）。
///
/// **手机**：全局竖屏锁定。整棵 UI 树按竖屏单列布局设计（阅读页段落流、
/// 查词弹窗、统计卡片、底部导航），旋转到横屏只会得到拉伸错位的界面；
/// 也没有需要横屏的场景（无横屏视频、无大图查看）。
///
/// **平板**（最短边 ≥ 600dp）：不锁，横屏即首选形态——窗口 ≥ 840dp 时阅读页
/// 进入书页式两屏模式（见 [reading-spread.md]），竖屏回落单列 + 左导航栏。
///
/// 双保险（手机）：
/// - 本文件（Dart 侧）：引擎启动后调用，覆盖运行期旋转；
/// - 原生侧（`AndroidManifest.xml` 的 `android:screenOrientation="portrait"`、
///   iOS `Info.plist` 的 `UISupportedInterfaceOrientations`）：覆盖 Flutter
///   引擎启动前的启动窗口（闪屏期），避免冷启动瞬间先横屏再回正。
///
/// **为什么平板要显式请求四方向（fullUser）而不是空列表**：
///
/// - 空列表在 Flutter 里映射为 `unspecified`，而 `unspecified` 会**回落到
///   manifest 的声明**（本 App 是 `portrait`）——等于没解，窗口仍被 letterbox
///   成 666×813dp，永远进不了书页模式（2026-09-17 真机实测踩过这个坑）。
/// - 四方向列表映射为 `fullUser`（见 `SystemChrome` 文档的 Android 组合表），
///   是 Flutter API 能表达的最宽松值。
///
/// Android 16 官方说大屏会忽略方向声明，但实测小米 HyperOS（Android 16 /
/// targetSdk 36 / sw813dp）**并未启用该行为**——它按 manifest 把窗口 letterbox
/// 成竖屏。既然本 ROM 仍听从运行时请求，平板侧就主动请求 fullUser 换取铺满。
///
/// 注意：manifest 仍保留 portrait——它决定启动窗口；运行期的平板解限由本函数
/// 完成，手机侧行为与改造前完全一致。
Future<void> applyOrientationPolicy() async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  // letterbox 时 physicalSize 报的是 letterbox 后的尺寸（Flutter 文档明确
  // 提示：判定屏幕档位要用 display）。但此处的判定目的是「这台设备是不是
  // 平板」，letterbox 后的最短边同样 ≥ 600dp（实测 666dp），故仍可用；
  // 真正的宽度档位判定交给 MediaQuery（布局侧）。
  final logicalSize = view.physicalSize / view.devicePixelRatio;
  if (logicalSize.shortestSide >= kMediumWidthBreakpoint) {
    // 平板：四方向全允许（fullUser），让窗口铺满、随设备旋转
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    return;
  }
  await lockAppToPortrait();
}

/// 手机：固定竖屏。
///
/// 只锁 `portraitUp`（固定竖屏），不传 `[portraitUp, portraitDown]`：
/// 后者在 Android 上映射为 userPortrait，倒竖屏是否生效取决于系统
/// 「自动旋转」开关状态，不如固定竖屏确定。
Future<void> lockAppToPortrait() {
  return SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
}
