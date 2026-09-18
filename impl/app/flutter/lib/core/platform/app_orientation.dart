import 'package:flutter/services.dart';

import 'device_form_factor.dart';

/// 方向策略（2026-09-18 起由 [DeviceFormFactor] 驱动，**两档都锁死、都不允许翻转**）。
///
/// | 设备 | 请求 | 安卓映射 | 效果 |
/// |------|------|---------|------|
/// | 手机（最短边 < 600dp） | `[portraitUp]` | `portrait` | 固定竖屏 |
/// | 平板（最短边 ≥ 600dp） | `[landscapeLeft]` | `landscape` | 固定横屏 |
///
/// **手机**：整棵界面树（`lib/ui/`）按竖屏单列布局设计。
///
/// **平板**：整棵界面树（`lib/pad/`）按横屏「左导航 + 宽内容区」设计，
/// 横屏是唯一形态。
///
/// **「不翻转」怎么做到**：Flutter 把方向列表映射为安卓的 `screenOrientation`
/// 组合——单元素列表给出**固定方向**（`portrait` / `landscape`），双元素给出
/// `userXxx`（跟随系统自动旋转开关，允许 180° 翻转），四元素给出 `fullUser`。
/// 所以两档都只传单元素列表。
///
/// 双保险：
/// - 本文件（Dart 侧）：引擎启动后调用，覆盖运行期旋转；
/// - 原生侧（`AndroidManifest.xml`）：覆盖 Flutter 引擎启动前的启动窗口
///   （闪屏期），避免冷启动瞬间先竖屏再回正。
///
/// **Android 16 大屏的额外一关**（2026-09-18 实测）：targetSdk ≥ 36 的 App
/// 在 sw ≥ 600dp 的大屏上，方向限制会被系统整体忽略
/// （`dumpsys window displays` 里 `ignoreOrientationRequest=true`）。需要在
/// manifest 里声明 `android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`
/// 才能恢复"系统尊重方向声明"的兼容模式。详见 docs/app-orientation.md。
Future<void> applyOrientationPolicy(DeviceFormFactor formFactor) {
  return switch (formFactor) {
    DeviceFormFactor.pad => lockAppToLandscape(),
    DeviceFormFactor.phone => lockAppToPortrait(),
  };
}

/// 平板：固定横屏，**不允许翻转**。
///
/// 只传 `landscapeLeft`（单元素）→ 安卓 `landscape`（固定），而不是
/// `landscapeLeft + landscapeRight`（→ `userLandscape`，两个横屏方向都
/// 允许、可 180° 翻转）。界面按「左导航栏 + 右侧内容区」的单向布局设计，
/// 翻转 180° 会让导航栏跑到右手侧，与设计不符。
///
/// 已知代价：用户把平板反向拿时，界面相对用户是倒的。这是「不允许翻转」的
/// 直接后果，不做运行时补救。
Future<void> lockAppToLandscape() {
  return SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
  ]);
}

/// 手机：固定竖屏，**不允许翻转**。
///
/// 只锁 `portraitUp`（单元素 → 安卓 `portrait`，固定竖屏），不传
/// `[portraitUp, portraitDown]`：后者映射为 `userPortrait`，倒竖屏是否生效
/// 取决于系统「自动旋转」开关状态，不如固定竖屏确定。
Future<void> lockAppToPortrait() {
  return SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
}
