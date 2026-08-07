/// yyyy-MM-dd（本地日期）
String isoLocalDate(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// yyyy-MM-dd'T'HH:mm:ss+HH:MM（本地时区偏移，与 Room 的 DateTimeFormatter.ISO_OFFSET_DATE_TIME 一致）
String isoOffsetDateTime(DateTime t) {
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final a = offset.abs();
  final h = (a.inHours).toString().padLeft(2, '0');
  final m = (a.inMinutes % 60).toString().padLeft(2, '0');
  final hms = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  return '${isoLocalDate(t)}T$hms$sign$h:$m';
}

/// Unix 毫秒
int nowMillis() => DateTime.now().millisecondsSinceEpoch;
