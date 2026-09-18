import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 本机号码读取（MethodChannel → MainActivity.kt telephonyManager.line1Number）。
///
/// 已知限制（见 MainActivity.kt 注释 / README）：
/// - 无 READ_PHONE_STATE 权限 / 权限被拒 → 返回 null（走手动输入）；
/// - Android 26+ 多数设备 line1Number 返回 null（运营商不给 SIM 卡号码），
///   属于平台已知限制，同样回退手动输入；
/// - iOS 无对应系统 API（MethodChannel 仅 Android 侧实现），
///   [supportsLine1Number] 为 false，登录页据此直接展示手动输入框，
///   而不是点了才展开。
class NativePhoneReader {
  static const _channel = MethodChannel('contexta/native');

  /// 当前平台是否支持读取本机号码（仅 Android 有运营商 line1Number）。
  ///
  /// 实例成员而非静态：测试宿主（macOS）上静态平台判断恒为 false，登录页
  /// 会整体走 iOS 分支；做成实例成员后测试注入 fake 即可覆盖两种形态。
  bool get supportsLine1Number => Platform.isAndroid;

  /// 读取本机号码；不可用（无权限 / 平台不支持 / 通道异常）返回 null，不抛。
  Future<String?> readLine1Number() async {
    try {
      return await _channel.invokeMethod<String>('getLine1Number');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
