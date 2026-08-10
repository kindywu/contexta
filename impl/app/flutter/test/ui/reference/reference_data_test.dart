import 'package:contexta/ui/reference/reference_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页静态数据测试（对照 Kotlin GrammarDataTest + SpeakTextTest）：
/// - 语法数据完整性（4 组 23 条、字段齐全、例句成对）
/// - 字母表 / 音标分组规模
/// - phoneme 拟音映射全覆盖（48 个音标均有映射）
/// - speak 文本规则（字母格先读字母名，音标格只读例词）

void main() {
  group('语法数据', () {
    test('grammarGroups 四组，名称与条目数正确', () {
      expect(
        grammarGroups.map((g) => g.name),
        ['时态', '词形变化', '功能词', '句式'],
      );
      expect(grammarGroups.map((g) => g.items.length), [6, 6, 5, 6]);
    });

    test('全部语法条目字段齐全、例句成对', () {
      final all = grammarGroups.expand((g) => g.items).toList();
      expect(all.length, 23);
      for (final item in all) {
        expect(item.name.trim(), isNotEmpty);
        expect(item.explanation.trim(), isNotEmpty);
        expect(item.chineseExplanation.trim(), isNotEmpty);
        expect(item.examples, isNotEmpty);
        for (final (en, zh) in item.examples) {
          expect(en.trim(), isNotEmpty);
          expect(zh.trim(), isNotEmpty);
        }
      }
    });
  });

  group('字母表与音标数据', () {
    test('字母表 26 项，字段齐全', () {
      expect(alphabetData.length, 26);
      for (final item in alphabetData) {
        expect(item.char, isNotEmpty);
        expect(item.phone, startsWith('/'));
        expect(item.example, isNotEmpty);
        expect(item.cn, isNotEmpty);
      }
    });

    test('音标分组：8 组 48 个音标', () {
      final all = phonicsGroups.expand((g) => g.items).toList();
      expect(all.length, 48);
      expect(phonicsGroups.map((g) => g.name), [
        '单元音 (12)',
        '双元音 (8)',
        '爆破音 (6)',
        '摩擦音 (10)',
        '破擦音 (6)',
        '鼻辅音 (3)',
        '舌侧音 (1)',
        '半元音 (2)',
      ]);
    });
  });

  group('phoneme 拟音映射', () {
    test('网格中每个音标都有拟音映射', () {
      final phones = phonicsGroups.expand((g) => g.items).map((i) => i.phone);
      for (final phone in phones) {
        expect(phonemeOwnSound(phone), isNotNull,
            reason: 'missing own-sound mapping for $phone');
      }
    });

    test('抽查映射值', () {
      expect(phonemeOwnSound('/iː/'), 'ee');
      expect(phonemeOwnSound('/æ/'), 'ack');
      expect(phonemeOwnSound('/b/'), 'buh');
      expect(phonemeOwnSound('/aɪ/'), 'eye');
      expect(phonemeOwnSound('/ŋ/'), 'nguh');
    });

    test('未知音标返回 null', () {
      expect(phonemeOwnSound('/zzz/'), isNull);
    });
  });

  group('speak 文本规则', () {
    const alphabetCell = ReferenceCellData(
      char: 'A a',
      reading: '/eɪ/',
      example: 'Apple',
      exampleCn: '苹果',
      isPhonetic: false,
    );

    test('字母格：先读字母名再读例词（句号停顿）', () {
      expect(speakTextFor(alphabetCell), 'A. Apple');
    });

    test('多字符字母取首字符大写', () {
      const w = ReferenceCellData(
        char: 'W w',
        reading: '/ˈdʌbljuː/',
        example: 'Water',
        exampleCn: '水',
        isPhonetic: false,
      );
      expect(speakTextFor(w), 'W. Water');

      const x = ReferenceCellData(
        char: 'X x',
        reading: '/eks/',
        example: 'X-ray',
        exampleCn: 'X光',
        isPhonetic: false,
      );
      expect(speakTextFor(x), 'X. X-ray');
    });

    test('音标格：只读例词', () {
      const cell = ReferenceCellData(
        char: '/eɪ/',
        reading: '单元音 (12)',
        example: 'see',
        exampleCn: '',
        isPhonetic: true,
      );
      expect(speakTextFor(cell), 'see');
    });

    test('音标格 own sound：映射优先，缺失兜底例词', () {
      const cell = ReferenceCellData(
        char: '/iː/',
        reading: '单元音 (12)',
        example: 'see',
        exampleCn: '',
        isPhonetic: true,
      );
      expect(ownSoundFor(cell), 'ee');

      const unknown = ReferenceCellData(
        char: '/??/',
        reading: 'x',
        example: 'see',
        exampleCn: '',
        isPhonetic: true,
      );
      expect(ownSoundFor(unknown), 'see');
    });

    test('字母格 own sound 是字母名', () {
      expect(ownSoundFor(alphabetCell), 'A');
    });
  });
}
