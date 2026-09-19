/// 会话设备信息（服务端 login/preview 的 evicted 列表、401 EVICTED detail 的 by 字段）。
///
/// 展示口径统一走 [deviceLabel]：`机型 · 短码`（短码 = device_id 后 4 位），
/// 机型缺失（旧版本 App 上报 / 老会话行）→ 「未知设备」。
class SessionDevice {
  const SessionDevice({
    required this.deviceId,
    required this.issuedAtMillis,
    this.deviceName,
  });

  final String deviceId;
  final String? deviceName;

  /// 该会话的签发时刻（Unix 毫秒）——展示为"该设备登录时间"。
  final int issuedAtMillis;

  factory SessionDevice.fromJson(Map<String, dynamic> json) => SessionDevice(
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String?,
        issuedAtMillis: (json['issued_at'] as num).toInt(),
      );
}

/// 设备展示名：`机型 · 短码`（短码取 device_id 末 4 位；不足 4 位全取）。
String deviceLabel(String? deviceName, String deviceId) {
  final name = (deviceName == null || deviceName.isEmpty) ? '未知设备' : deviceName;
  final tail = deviceId.length <= 4
      ? deviceId
      : deviceId.substring(deviceId.length - 4);
  return '$name · $tail';
}
