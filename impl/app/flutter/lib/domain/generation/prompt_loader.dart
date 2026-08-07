import 'package:flutter/services.dart' show rootBundle;

/// 加载 prompt 模板文件（对照 Kotlin PromptLoader.kt）。
///
/// 模板可含 `=== SECTION_NAME ===` 分隔的节，用 [loadSection] 提取并
/// 替换 `{{key}}` 占位符。文件布局：
/// ```
/// === COMMON ===
/// shared content
///
/// === LOW ===
/// difficulty-specific content
///
/// === USER_PROMPT ===
/// template for user prompt
/// ```
///
/// Kotlin 从 classpath resources 读取；Dart 从 Flutter assets 读取
/// （pubspec 已声明 `assets/prompts/`）。
class PromptLoader {
  static const _sectionRegex =
      r'=== (\w+) ===\s*\n?(.*?)(?=\n=== |\Z)';

  /// 读取模板文件原始内容（去尾部空白）。读取失败返回 [fallback]。
  Future<String> load(String fileName, String fallback) async {
    try {
      final content = await rootBundle.loadString('assets/prompts/$fileName');
      return content.trimRight();
    } catch (_) {
      return fallback;
    }
  }

  /// 读取一个或多个命名节并拼接，替换占位符。
  /// 文件或任一请求的节缺失时返回 [fallback]。
  Future<String> loadSection(
    String fileName,
    List<String> sections, {
    Map<String, String> params = const {},
    required String fallback,
  }) async {
    final content = await load(fileName, fallback);
    if (content == fallback) return fallback;

    // 解析所有节到 map（Dart 正则不支持 groupValues 重复捕获，
    // 用全局匹配遍历，与 Kotlin findAll 语义一致）
    final sectionMap = <String, String>{};
    final re = RegExp(_sectionRegex, dotAll: true);
    for (final m in re.allMatches(content)) {
      sectionMap[m.group(1)!] = m.group(2)!.trim();
    }

    // 从请求的节构建结果
    final parts = [for (final s in sections) if (sectionMap.containsKey(s)) sectionMap[s]!];
    if (parts.isEmpty) return fallback;

    var result = parts.join('\n\n');
    for (final entry in params.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }
}
