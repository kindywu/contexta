/// KittenTTS 朗读音色（8 个内置音色，对齐 SDK kit.voice.*）。
///
/// dbValue 存 DB（大写枚举名，与 DifficultyLevel 模式一致）；
/// sdkVoiceId 为 KittenTTS 插件的 voice id（小写名，= 枚举名）。
enum TtsVoice {
  bella('BELLA', '贝拉 · Bella', 'Bella', true),
  jasper('JASPER', '贾斯帕 · Jasper', 'Jasper', false),
  luna('LUNA', '露娜 · Luna', 'Luna', true),
  bruno('BRUNO', '布鲁诺 · Bruno', 'Bruno', false),
  rosie('ROSIE', '罗茜 · Rosie', 'Rosie', true),
  hugo('HUGO', '雨果 · Hugo', 'Hugo', false),
  kiki('KIKI', '奇奇 · Kiki', 'Kiki', true),
  leo('LEO', '莱奥 · Leo', 'Leo', false);

  const TtsVoice(this.dbValue, this.label, this.englishName, this.isFemale);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  /// 设置页显示标签（中文 · 英文）。
  final String label;

  /// 英文名（试听例句嵌入用）。
  final String englishName;

  final bool isFemale;

  /// KittenTTS 插件 voice id（= 枚举名小写，与 SDK kit.voice.* 常量一致）。
  String get sdkVoiceId => name;

  static TtsVoice fromDbValue(String value) {
    for (final v in values) {
      if (v.dbValue == value) return v;
    }
    throw ArgumentError('Unknown TtsVoice: $value');
  }
}
