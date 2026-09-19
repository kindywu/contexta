import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 为系统「窗口控件」让出的左侧宽度（仅 iOS 非零；Android 无此控件）。
///
/// iPadOS 26+ 窗口化运行时，系统在窗口左上角悬浮一枚「…」窗口控件胶囊，
/// **画在应用内容之上**（`Info.plist` 设 `UIRequiresFullScreen` 也不生效，
/// 2026-09-19 模拟器实测）——页面左上角的返回键/标题会被它盖住。左侧内容
/// 整体右让这么多即可避开：96dp ≈ 胶囊宽（约 82dp）+ 左间距（约 8dp）+ 余量。
///
/// ⚠️ 只用于**平板树**（`lib/pad/` 与跑在平板上的共享页）。手机树（iPhone）
/// 没有窗口控件，不应使用本值——调用方按设备形态（`formFactorProvider`）判断。
double get systemWindowControlsLeftInset =>
    windowControlsLeftInsetFor(isIOS: Platform.isIOS);

/// 纯函数版本（可测）：iOS → 96，其余平台 → 0。
@visibleForTesting
double windowControlsLeftInsetFor({required bool isIOS}) => isIOS ? 96 : 0;
