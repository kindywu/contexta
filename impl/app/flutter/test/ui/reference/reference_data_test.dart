import 'dart:io';

import 'package:contexta/domain/audio/phoneme_audio.dart';
import 'package:contexta/ui/reference/reference_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页静态数据测试（对照 Kotlin GrammarDataTest + SpeakTextTest）：
/// - 语法数据完整性（4 组 23 条、字段齐全、例句成对）
/// - 字母表 / 音标分组规模
/// - 音标录音齐全（manifest 覆盖 48 个音标、文件真实存在）
/// - speak 文本规则（字母格先读字母名再读例词；音标格不走 TTS）

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
        expect(item.full, startsWith('/'), reason: 'missing IPA for ${item.example}');
        expect(item.full, endsWith('/'));
        expect(item.cn, isNotEmpty);
      }
    });

    test('音标分组每项都有例词完整音标', () {
      for (final item in phonicsGroups.expand((g) => g.items)) {
        expect(item.full, startsWith('/'), reason: 'missing IPA for ${item.example}');
        expect(item.full, endsWith('/'));
      }
    });

    test('音标分组：8 组 48 个音标', () {
      final all = phonicsGroups.expand((g) => g.items).toList();
      expect(all.length, 48);
      // 组名不带条目数——标题上的 "(N)" 由 reference_screen 按 items.length 拼，
      // 弹窗注脚直接用组名（否则单个音标旁边挂个数字会被当成它的属性）
      expect(phonicsGroups.map((g) => g.name), [
        '单元音',
        '双元音',
        '爆破音',
        '摩擦音',
        '破擦音',
        '鼻辅音',
        '舌侧音',
        '半元音',
      ]);
      expect(phonicsGroups.map((g) => g.items.length), [12, 8, 6, 10, 6, 3, 1, 2]);
    });
  });

  group('音标录音（assets/phonetics/）', () {
    // 这组是「网格里每个音标都出得了声」的守门人：抓取脚本换人声/改文件名后，
    // 一旦与 phonicsGroups 的 48 个符号对不上，这里直接红。
    final manifestFile = File('assets/phonetics/manifest.json');

    test('manifest.json 存在且覆盖全部 48 个音标', () {
      expect(manifestFile.existsSync(), isTrue,
          reason: '缺 assets/phonetics/manifest.json——跑 tool/fetch-phonetics-yyb.ts 生成');

      final files = phonemeFilesFromManifest(manifestFile.readAsStringSync());
      final phones = phonicsGroups.expand((g) => g.items).map((i) => i.phone);
      for (final phone in phones) {
        expect(files[normalizePhone(phone)], isNotNull, reason: '音标 $phone 没有对应录音');
      }
    });

    test('manifest 里每个文件都真实存在（非空）', () {
      final files = phonemeFilesFromManifest(manifestFile.readAsStringSync());
      expect(files, isNotEmpty);
      for (final entry in files.entries) {
        final f = File('assets/phonetics/${entry.value}');
        expect(f.existsSync(), isTrue, reason: '${entry.key} → ${entry.value} 不在盘上');
        expect(f.lengthSync(), greaterThan(512), reason: '${entry.value} 内容可疑');
      }
    });
  });

  group('speak 文本规则', () {
    const alphabetCell = ReferenceCellData(
      char: 'A a',
      reading: '/eɪ/',
      example: 'Apple',
      exampleIpa: '/ˈæpəl/',
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
        exampleIpa: '/ˈwɔːtə/',
        exampleCn: '水',
        isPhonetic: false,
      );
      expect(speakTextFor(w), 'W. Water');

      const x = ReferenceCellData(
        char: 'X x',
        reading: '/eks/',
        example: 'X-ray',
        exampleIpa: '/ˈeksreɪ/',
        exampleCn: 'X光',
        isPhonetic: false,
      );
      expect(speakTextFor(x), 'X. X-ray');
    });

    test('音标格：TTS 只念例词，音标本身交给录音（不把 IPA 送进 TTS）', () {
      const cell = ReferenceCellData(
        char: '/iː/',
        reading: '单元音 (12)',
        example: 'see',
        exampleIpa: '/siː/',
        exampleCn: '',
        isPhonetic: true,
      );
      expect(speakTextFor(cell), 'see');
    });

    test('未知音标同样只念例词（不因缺录音把 IPA 送进 TTS）', () {
      const unknown = ReferenceCellData(
        char: '/??/',
        reading: 'x',
        example: 'see',
        exampleIpa: '/siː/',
        exampleCn: '',
        isPhonetic: true,
      );
      expect(speakTextFor(unknown), 'see');
    });
  });
}
