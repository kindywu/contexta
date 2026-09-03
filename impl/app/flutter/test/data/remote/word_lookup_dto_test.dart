import 'package:contexta/data/remote/dto/word_lookup_dto.dart';
import 'package:flutter_test/flutter_test.dart';

/// WordLookupDto 映射测试（Task 7 查词远程化）：
/// 服务端 /api/llm/word-lookup 响应 data → WordDetail 全字段映射 + 缺省处理。
void main() {
  // 服务端契约完整形态（字段名精确 snake_case，见 dto 注释）
  const fullJson = {
    'spelling': 'serendipity',
    'phonetic': '/ˌserənˈdɪpəti/',
    'senses': [
      {
        'order_index': 1,
        'part_of_speech': 'n.',
        'chinese_meaning': '意外发现珍奇事物的运气',
        'english_definition':
            'The occurrence and development of events by chance in a happy or beneficial way.',
        'examples': [
          {
            'order_index': 1,
            'sentence_en': 'It was pure serendipity that we met.',
            'sentence_zh': '我们的相遇纯属幸运。',
            'is_primary': true,
          },
          {
            'order_index': 2,
            'sentence_en': 'Finding that book was a stroke of serendipity.',
            'sentence_zh': '找到那本书纯属意外之喜。',
            'is_primary': false,
          },
        ],
      },
      {
        'order_index': 2,
        'part_of_speech': 'adj.',
        'chinese_meaning': '幸运的',
        'english_definition': 'Lucky or fortunate.',
        'examples': <Map<String, Object>>[],
      },
    ],
  };

  test('完整 JSON → WordDetail 全字段映射正确', () {
    final dto = WordLookupDto.fromJson(fullJson);
    final detail = dto.toWordDetail();

    // 无 DB ID（落库前）：wordId/义项 id/例句 id 均为 0
    expect(detail.wordId, 0);
    expect(detail.spellingDisplay, 'serendipity');
    expect(detail.phoneticIpa, '/ˌserənˈdɪpəti/');
    expect(detail.isInVocabulary, isFalse);
    expect(detail.vocabularyEntryId, isNull);
    // 词形解析标注：远程结果不含（阅读页按精确命中处理）
    expect(detail.inflection, isNull);

    // primarySense = 首个义项（语义等同 allSenses.first：同 orderIndex/词性/释义）
    expect(detail.primarySense!.orderIndex, detail.allSenses.first.orderIndex);
    expect(
      detail.primarySense!.chineseMeaning,
      detail.allSenses.first.chineseMeaning,
    );
    expect(detail.allSenses, hasLength(2));

    final first = detail.allSenses[0];
    expect(first.id, 0);
    expect(first.orderIndex, 1);
    expect(first.partOfSpeech, 'n.');
    expect(first.chineseMeaning, '意外发现珍奇事物的运气');
    expect(
      first.englishDefinition,
      contains('occurrence and development'),
    );
    expect(first.examples, hasLength(2));

    final ex1 = first.examples[0];
    expect(ex1.id, 0);
    expect(ex1.orderIndex, 1);
    expect(ex1.sentenceEn, 'It was pure serendipity that we met.');
    expect(ex1.sentenceZh, '我们的相遇纯属幸运。');
    expect(ex1.isPrimary, isTrue);

    final ex2 = first.examples[1];
    expect(ex2.orderIndex, 2);
    expect(ex2.isPrimary, isFalse);

    final second = detail.allSenses[1];
    expect(second.orderIndex, 2);
    expect(second.partOfSpeech, 'adj.');
    expect(second.chineseMeaning, '幸运的');
    expect(second.examples, isEmpty);
  });

  test('服务端缺 phonetic → phoneticIpa 为 null', () {
    final dto = WordLookupDto.fromJson({
      'spelling': 'hello',
      'senses': [
        {
          'order_index': 1,
          'part_of_speech': 'interj.',
          'chinese_meaning': '你好',
          'english_definition': 'Used as a greeting.',
          'examples': <Map<String, Object>>[],
        },
      ],
    });
    final detail = dto.toWordDetail();

    expect(detail.spellingDisplay, 'hello');
    expect(detail.phoneticIpa, isNull);
    expect(detail.allSenses, hasLength(1));
    expect(detail.allSenses.first.chineseMeaning, '你好');
  });

  test('senses 空 → 解析失败（FormatException，调用点按降级处理）', () {
    final dto = WordLookupDto.fromJson({
      'spelling': 'nope',
      'senses': <Map<String, Object>>[],
    });

    expect(dto.toWordDetail, throwsFormatException);
  });
}
