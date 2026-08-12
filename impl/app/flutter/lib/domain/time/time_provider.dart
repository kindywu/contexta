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

  /// 明天日期字符串（手机时区，ISO 格式 yyyy-MM-dd）。
  /// 2026-08-12：预生成批次打"明天"日期——今天消费的批次（generated_on=今天）
  /// 仍占用 UNIQUE(difficulty, generated_on)，预生成必须落在不同日期；
  /// 且"明天"日期天然满足消费规则（>= 最后消费日），断签多天依然可消费。
  String nextDateString();
}
