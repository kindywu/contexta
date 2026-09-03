import 'package:flutter/services.dart';

/// 本机号码读取（MethodChannel → MainActivity.kt telephonyManager.line1Number）。
///
/// 已知限制（见 MainActivity.kt 注释 / README）：
/// - 无 READ_PHONE_STATE 权限 / 权限被拒 → 返回 null（走手动输入）；
/// - Android 26+ 多数设备 line1Number 返回 null（运营商不给 SIM 卡号码），
///   属于平台已知限制，同样回退手动输入。
class NativePhoneReader {
  static const _channel = MethodChannel('contexta/native');

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
