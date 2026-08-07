/// 提供应用元信息，供错误上报使用（对照 Kotlin AppInfoProvider.kt）。
/// 接口在 domain，实现在 data/（从 platform channel 取值）。
abstract interface class AppInfoProvider {
  /// 应用版本号（versionCode）。
  int get versionCode;

  /// 应用版本名（versionName）。
  String get versionName;

  /// 设备型号（如 "Xiaomi 14"）。
  String get deviceModel;
}
