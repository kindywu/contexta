/// 通知时间展示：`MM-dd HH:mm`（本地时区）。
String formatNoticeTime(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
