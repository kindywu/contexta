import '../../core/time/iso8601.dart';
import 'time_provider.dart';

/// 生产 TimeProvider（真实时钟，对照 Kotlin TimeProvider）。
///
/// 独立文件而非 providers.dart 私有类（2026-08-14 计划 B Task 8 提取）：
/// 后台 isolate 的 syncCallbackDispatcher 与 UI 注入共用同一实现，
/// 避免后台代码依赖 riverpod。
class ProdTimeProvider implements TimeProvider {
  @override
  int nowMillis() => DateTime.now().millisecondsSinceEpoch;

  @override
  String nowDateTimeString() => isoOffsetDateTime(DateTime.now());

  @override
  String todayDateString() => isoLocalDate(DateTime.now());

  @override
  String nextDateString() =>
      isoLocalDate(DateTime.now().add(const Duration(days: 1)));
}
