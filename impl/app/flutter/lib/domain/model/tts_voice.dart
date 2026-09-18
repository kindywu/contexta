import 'dart:math';

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

  /// 随机挑一个音色（男女不限，8 个音色等概率）。
  static TtsVoice pickRandom(Random random) =>
      values[random.nextInt(values.length)];

  static TtsVoice fromDbValue(String value) {
    for (final v in values) {
      if (v.dbValue == value) return v;
    }
    throw ArgumentError('Unknown TtsVoice: $value');
  }

  /// 宽松解析：null / 未知值返回 null（不抛）——用于**读库**场景
  /// （article.tts_voice_id 由本应用写入，未知值按「未分配」处理，不让
  /// 整个阅读页加载失败）；设置值解析仍用严格的 [fromDbValue]。
  static TtsVoice? tryFromDbValue(String? value) {
    if (value == null) return null;
    for (final v in values) {
      if (v.dbValue == value) return v;
    }
    return null;
  }
}

/// 朗读音色设置（`user_settings.tts_voice_id` 的领域表示）：
/// - [TtsVoiceSetting.random]：随机（**默认**）——阅读页每篇文章首次朗读时
///   随机分配一个音色并持久化到 `article.tts_voice_id`，此后该文章固定；
/// - [TtsVoiceSetting.fixed]：用户显式选定音色，全站朗读一律用它，不随机。
///
/// 与 [TtsVoice] 分开而非加一个 `TtsVoice.random` 枚举值：引擎接口
/// `speak(voice: TtsVoice)` 只接受**具体**音色，把「随机」挡在枚举外，
/// 编译期即保证发声前已完成解析（随机值漏进 SDK 会被当成未知 voice id）。
class TtsVoiceSetting {
  /// 随机（默认）。
  const TtsVoiceSetting.random() : voice = null;

  /// 固定音色。
  const TtsVoiceSetting.fixed(TtsVoice this.voice);

  /// DB 存储值：随机哨兵 `'RANDOM'` 或具体音色的 dbValue。
  static const String randomDbValue = 'RANDOM';

  /// 具体音色；null = 随机。
  final TtsVoice? voice;

  bool get isRandom => voice == null;

  /// 设置页 / 阅读页显示标签（随机或具体音色的 label）。
  String get label => voice?.label ?? '随机';

  String get dbValue => voice?.dbValue ?? randomDbValue;

  static TtsVoiceSetting fromDbValue(String value) => value == randomDbValue
      ? const TtsVoiceSetting.random()
      : TtsVoiceSetting.fixed(TtsVoice.fromDbValue(value));

  @override
  bool operator ==(Object other) =>
      other is TtsVoiceSetting && other.voice == voice;

  @override
  int get hashCode => voice.hashCode;

  @override
  String toString() => dbValue;
}
