/// 时间抽象接口（对照 Kotlin TimeProvider.kt），替换所有直接的时间调用。
/// 测试中通过 Fake 固定时间，确保可重复性。
abstract interface class TimeProvider {
  /// 当前 Unix 毫秒时间戳（仅用于内存计算，如飞书去重窗口、签名）。
  int nowMillis();

  /// 当前日期时间字符串（手机时区，ISO 8601 秒级带 offset，
  /// 如 "2026-07-31T10:30:00+08:00"）。用于所有落库时间字段。
  String nowDateTimeString();

  /// 当前日期字符串（手机时区，ISO 格式 yyyy-MM-dd）。
  String todayDateString();
}
