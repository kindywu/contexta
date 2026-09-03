import '../../../domain/model/word_detail.dart';

/// 服务端查词 DTO（POST /api/llm/word-lookup 契约，字段名精确 snake_case）：
///
/// ```json
/// {spelling, phonetic?, senses: [{order_index, part_of_speech,
///  chinese_meaning, english_definition, examples: [{order_index, sentence_en,
///  sentence_zh, is_primary}]}]}
/// ```
///
/// 无 DB ID（wordId / 义项 id / 例句 id = 0，落库前形态，与旧本地解析结果一致）。
class WordLookupDto {
  const WordLookupDto({
    required this.spelling,
    required this.phonetic,
    required this.senses,
  });

  final String spelling;

  /// 服务端可为 null（未知音标时缺省）。
  final String? phonetic;

  final List<WordSenseDto> senses;

  factory WordLookupDto.fromJson(Map<String, dynamic> json) => WordLookupDto(
    spelling: json['spelling'] as String,
    phonetic: json['phonetic'] as String?,
    senses: [
      for (final s in (json['senses'] as List? ?? const []))
        WordSenseDto.fromJson((s as Map).cast<String, dynamic>()),
    ],
  );

  /// → 领域模型 [WordDetail]。
  ///
  /// 服务端保证 senses ≥ 1；空义项视为解析失败（抛 [FormatException]，
  /// 调用点按既有降级语义处理：阅读页「仅词头」/ 加词页拼写提示）。
  WordDetail toWordDetail() {
    if (senses.isEmpty) {
      throw const FormatException('word-lookup 返回空义项（senses 为空）');
    }
    return WordDetail(
      wordId: 0,
      spellingDisplay: spelling,
      phoneticIpa: phonetic,
      primarySense: senses.first.toDomain(),
      allSenses: [for (final s in senses) s.toDomain()],
      isInVocabulary: false,
      vocabularyEntryId: null,
    );
  }
}

/// 义项 DTO（服务端契约 {order_index, part_of_speech, chinese_meaning,
/// english_definition, examples}）。
class WordSenseDto {
  const WordSenseDto({
    required this.orderIndex,
    required this.partOfSpeech,
    required this.chineseMeaning,
    required this.englishDefinition,
    required this.examples,
  });

  final int orderIndex;
  final String partOfSpeech;
  final String chineseMeaning;
  final String englishDefinition;
  final List<ExampleSentenceDto> examples;

  factory WordSenseDto.fromJson(Map<String, dynamic> json) => WordSenseDto(
    orderIndex: json['order_index'] as int,
    partOfSpeech: json['part_of_speech'] as String,
    chineseMeaning: json['chinese_meaning'] as String,
    englishDefinition: json['english_definition'] as String,
    examples: [
      for (final e in (json['examples'] as List? ?? const []))
        ExampleSentenceDto.fromJson((e as Map).cast<String, dynamic>()),
    ],
  );

  WordSense toDomain() => WordSense(
    id: 0,
    orderIndex: orderIndex,
    partOfSpeech: partOfSpeech,
    chineseMeaning: chineseMeaning,
    englishDefinition: englishDefinition,
    examples: [for (final e in examples) e.toDomain()],
  );
}

/// 例句 DTO（服务端契约 {order_index, sentence_en, sentence_zh, is_primary}）。
class ExampleSentenceDto {
  const ExampleSentenceDto({
    required this.orderIndex,
    required this.sentenceEn,
    required this.sentenceZh,
    required this.isPrimary,
  });

  final int orderIndex;
  final String sentenceEn;
  final String sentenceZh;
  final bool isPrimary;

  factory ExampleSentenceDto.fromJson(Map<String, dynamic> json) =>
      ExampleSentenceDto(
        orderIndex: json['order_index'] as int,
        sentenceEn: json['sentence_en'] as String,
        sentenceZh: json['sentence_zh'] as String,
        isPrimary: json['is_primary'] as bool,
      );

  ExampleSentence toDomain() => ExampleSentence(
    id: 0,
    orderIndex: orderIndex,
    sentenceEn: sentenceEn,
    sentenceZh: sentenceZh,
    isPrimary: isPrimary,
  );
}
