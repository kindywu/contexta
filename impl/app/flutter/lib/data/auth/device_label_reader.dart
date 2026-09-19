import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备机型名读取（MethodChannel `contexta/native` → Android Build / iOS utsname）。
///
/// 用途：登录时上报 `device_name`，多设备提示里展示「机型 · 短码」。
/// 不可用（通道缺失 / 异常）返回 null —— 服务端与 UI 均按「未知设备」降级，不阻断登录；
/// 降级本身留日志（不静默吞错）。
class DeviceLabelReader {
  static const _channel = MethodChannel('contexta/native');

  Future<String?> readDeviceLabel() async {
    try {
      final label = await _channel.invokeMethod<String>('getDeviceLabel');
      return (label == null || label.isEmpty) ? null : label;
    } on PlatformException catch (e) {
      debugPrint('[DeviceLabelReader] channel error, fallback to unknown device: '
          '${e.code} ${e.message}');
      return null;
    } on MissingPluginException catch (e) {
      debugPrint('[DeviceLabelReader] channel missing, fallback to unknown device: $e');
      return null;
    }
  }
}
