/// 译文显示模式（对照 Kotlin TranslationMode.kt）。
///
/// [full] 之外的模式均为 UI 显示状态；持久化用
/// [TranslationDisplayMode.fromDbValue]/[toDbValue]（DB 只存 FULL/BLURRED/HIDDEN，
/// 不存 DIM——DIM 是阅读页临时显示态）。
enum TranslationMode {
  /// 完全显示
  full('完全显示'),

  /// 淡化（alpha 0.55）
  dim('淡化'),

  /// 模糊（点击揭示，10 秒后自动重新模糊）
  blurred('模糊'),

  /// 隐藏
  hidden('隐藏');

  const TranslationMode(this.label);

  final String label;

  /// 循环顺序：FULL → DIM → BLURRED → HIDDEN → FULL。
  TranslationMode get next => values[(index + 1) % values.length];

  /// 从持久化字符串（大写 enum 名，含 'DIM'——Kotlin 会持久化循环中间态）
  /// 解析；未知值回退 [full]（对照 Kotlin try valueOf 兜底）。
  static TranslationMode fromStorage(String? value) {
    if (value == null) return full;
    for (final mode in values) {
      if (mode.name.toUpperCase() == value.toUpperCase()) return mode;
    }
    return full;
  }
}
