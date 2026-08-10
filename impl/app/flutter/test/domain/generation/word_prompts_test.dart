import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/domain/generation/word_prompts.dart';

void main() {
  group('parseWordLlmResponse', () {
    test('标准格式：<spelling> 根标签解析完整', () {
      const xml = '<spelling>ocean</spelling>\n'
          '<phonetic>/ˈoʊʃən/</phonetic>\n'
          '<sense>\n'
          '  <partOfSpeech>n.</partOfSpeech>\n'
          '  <chineseMeaning>海洋</chineseMeaning>\n'
          '  <englishDefinition>A large body of salt water.</englishDefinition>\n'
          '  <example>\n'
          '    <en>The ocean is deep.</en>\n'
          '    <zh>海洋很深。</zh>\n'
          '  </example>\n'
          '</sense>';

      final detail = parseWordLlmResponse(xml);
      expect(detail, isNotNull);
      expect(detail!.spellingDisplay, 'ocean');
      expect(detail.phoneticIpa, '/ˈoʊʃən/');
      expect(detail.allSenses, hasLength(1));
      expect(detail.allSenses.first.partOfSpeech, 'n.');
      expect(detail.allSenses.first.chineseMeaning, '海洋');
      expect(detail.allSenses.first.examples, hasLength(1));
      expect(detail.allSenses.first.examples.first.sentenceEn, 'The ocean is deep.');
    });

    test('容错：LLM 用查询词作根标签（<ocean>ocean</ocean>）仍能解析拼写', () {
      const xml = '<ocean>ocean</ocean>\n'
          '<phonetic>/ˈoʊʃən/</phonetic>\n'
          '<sense>\n'
          '  <partOfSpeech>n.</partOfSpeech>\n'
          '  <chineseMeaning>海洋</chineseMeaning>\n'
          '  <englishDefinition>A large body of salt water.</englishDefinition>\n'
          '  <example>\n'
          '    <en>The ocean is deep.</en>\n'
          '    <zh>海洋很深。</zh>\n'
          '  </example>\n'
          '</sense>';

      final detail = parseWordLlmResponse(xml);
      expect(detail, isNotNull);
      expect(detail!.spellingDisplay, 'ocean');
      expect(detail.phoneticIpa, '/ˈoʊʃən/');
      expect(detail.allSenses, hasLength(1));
    });

    test('无任何拼写信息 → 返回 null', () {
      expect(parseWordLlmResponse('plain text no tags'), isNull);
      expect(parseWordLlmResponse('<spelling></spelling>'), isNull);
      // 结构块不被兜底为拼写（非单词形态）
      expect(
        parseWordLlmResponse(
          '<phonetic>/x/</phonetic>\n<sense>\n'
          '  <partOfSpeech>n.</partOfSpeech>\n'
          '</sense>',
        ),
        isNull,
      );
    });

    test('无有效义项 → 返回 null', () {
      const xml = '<spelling>ocean</spelling>\n<phonetic>/x/</phonetic>';
      expect(parseWordLlmResponse(xml), isNull);
    });
  });
}
