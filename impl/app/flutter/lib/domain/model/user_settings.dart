/// 用户设置领域模型（对齐 Kotlin UserSettings.kt）。
///
/// [difficultyLevel] / [translationDisplayMode] 在 Kotlin 中为 String
/// （见注释的合法取值），此处保持一致；[DifficultyLevel] /
/// [TranslationDisplayMode] 枚举供 UI / 生成管道类型化使用。
class UserSettings {
  final int id;
  final bool isOnboarded;
  final String difficultyLevel; // LOW | MEDIUM | HIGH
  final int dailyArticleCount;
  final String translationDisplayMode; // FULL | BLURRED | HIDDEN
  final double ttsSpeed; // 0.8 | 1.0 | 1.2（UI 显示语速）
  final int masteryThresholdN;
  final bool autoPlayAudio;

  const UserSettings({
    this.id = 1,
    this.isOnboarded = false,
    this.difficultyLevel = 'MEDIUM',
    this.dailyArticleCount = 3,
    this.translationDisplayMode = 'FULL',
    this.ttsSpeed = 1.0,
    this.masteryThresholdN = 1,
    this.autoPlayAudio = false,
  });

  @override
  String toString() => 'UserSettings(id=$id, isOnboarded=$isOnboarded, '
      'difficultyLevel=$difficultyLevel, dailyArticleCount=$dailyArticleCount, '
      'translationDisplayMode=$translationDisplayMode, '
      'ttsSpeed=$ttsSpeed, '
      'masteryThresholdN=$masteryThresholdN, autoPlayAudio=$autoPlayAudio)';
}

/// 难度等级（LOW | MEDIUM | HIGH，存储层用大写枚举名 TEXT）。
enum DifficultyLevel {
  low('LOW'),
  medium('MEDIUM'),
  high('HIGH');

  const DifficultyLevel(this.dbValue);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  String toDbValue() => dbValue;

  static DifficultyLevel fromDbValue(String value) {
    for (final d in values) {
      if (d.dbValue == value) return d;
    }
    throw ArgumentError('Unknown DifficultyLevel: $value');
  }

  @override
  String toString() => dbValue;
}

/// 译文显示模式（对齐 Kotlin UI 层 TranslationMode 全集）。
///
/// 注意：[dim]（淡化）仅 UI 显示用，DB 只存 FULL/BLURRED/HIDDEN ——
/// [fromDbValue] 不映射 'DIM'，[toDbValue] 对 [dim] 抛 [StateError]。
enum TranslationDisplayMode {
  full('FULL'),
  dim('DIM'),
  blurred('BLURRED'),
  hidden('HIDDEN');

  const TranslationDisplayMode(this.dbValue);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  String toDbValue() => switch (this) {
        full => 'FULL',
        dim => throw StateError('TranslationDisplayMode.dim 仅 UI 显示用，禁止持久化'),
        blurred => 'BLURRED',
        hidden => 'HIDDEN',
      };

  static TranslationDisplayMode fromDbValue(String value) => switch (value) {
        'FULL' => full,
        'BLURRED' => blurred,
        'HIDDEN' => hidden,
        _ => throw ArgumentError('Unknown TranslationDisplayMode: $value'),
      };

  @override
  String toString() => dbValue;
}
