import 'package:flutter/services.dart';

/// 全局竖屏锁定（2026-09-11）。
///
/// Contexta 是单手持用的手机阅读类 App，整棵 UI 树按竖屏单列布局设计
/// （阅读页段落流、查词弹窗、统计卡片、底部导航都没有横屏适配），
/// 旋转到横屏只会得到拉伸错位的界面；也没有需要横屏的场景
/// （无横屏视频、无大图查看）。因此全局锁定竖屏，不提供按页面放开的入口。
///
/// 双保险：
/// - 本函数（Dart 侧）：引擎启动后调用，覆盖运行期旋转；
/// - 原生侧（`AndroidManifest.xml` 的 `android:screenOrientation="portrait"`、
///   iOS `Info.plist` 的 `UISupportedInterfaceOrientations`）：覆盖 Flutter
///   引擎启动前的启动窗口（闪屏期），避免冷启动瞬间先横屏再回正。
///
/// 只锁 `portraitUp`（固定竖屏），不传 `[portraitUp, portraitDown]`：
/// 后者在 Android 上映射为 userPortrait，倒竖屏是否生效取决于系统
/// 「自动旋转」开关状态，不如固定竖屏确定。
Future<void> lockAppToPortrait() {
  return SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
}
