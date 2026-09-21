import 'dart:convert';
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

  group('字母读音（复用音标录音）', () {
    // 这组是「字母表读音行」的守门人：读音行的例词/音标一律从 phonicsGroups 解析，
    // 音标库里没有的只有组合音白名单（自带例词、无录音）。
    const clusterWhitelist = {'/ks/', '/gz/'};

    test('26 个字母都有读音表，顺序与字母表一致', () {
      expect(letterSounds.map((g) => g.letter), alphabetData.map((i) => i.char.substring(0, 1)));
    });

    test('每条读音要么在音标库里（有录音），要么是组合音白名单（自带例词）', () {
      final phones = phonicsGroups
          .expand((g) => g.items)
          .map((i) => normalizePhone(i.phone))
          .toSet();
      for (final group in letterSounds) {
        expect(group.sounds, isNotEmpty, reason: '${group.letter} 一条读音都没有');
        for (final sound in group.sounds) {
          final inLibrary = phones.contains(normalizePhone(sound.phoneme));
          if (!inLibrary) {
            expect(clusterWhitelist, contains(sound.phoneme),
                reason: '${group.letter} 的 ${sound.phoneme} 不在音标库里，也不在组合音白名单');
            expect(sound.example, isNotNull, reason: '${group.letter} ${sound.phoneme} 缺例词');
          }
        }
      }
    });

    test('读音行：例词与音标取自音标库（同符号同一个词，才能配上例词录音）', () {
      final byPhone = {
        for (final item in phonicsGroups.expand((g) => g.items))
          normalizePhone(item.phone): item,
      };
      for (final group in letterSounds) {
        for (final row in soundRowsOf(group.letter)) {
          expect(row.example, isNotEmpty, reason: '${group.letter} ${row.phoneme} 缺例词');
          expect(row.exampleIpa, startsWith('/'), reason: row.example);
          expect(row.exampleIpa, endsWith('/'), reason: row.example);
          final item = byPhone[normalizePhone(row.phoneme)];
          if (item != null) {
            expect(row.hasAudio, isTrue, reason: '${row.phoneme} 在音标库里就该有录音');
            expect(row.example, item.example);
            expect(row.exampleIpa, item.full);
          } else {
            expect(row.hasAudio, isFalse, reason: '${row.phoneme} 没有录音');
            expect(row.note, isNotNull, reason: '没录音的读音行要注明原因');
          }
        }
      }
    });

    test('组合音：/ks/ /gz/ 无录音但带例词，X 三条读音齐全', () {
      final rows = soundRowsOf('X');
      expect(rows.map((r) => r.phoneme), ['/ks/', '/gz/', '/z/']);
      expect(rows.map((r) => r.hasAudio), [false, false, true]);
      expect(rows[0].example, isNotEmpty);
      expect(rows[1].example, isNotEmpty);
      expect(rows[2].kind, LetterSoundKind.minor);
    });

    test('读音行顺序与类别：A 五种、C 硬软音、O 六种', () {
      expect(soundRowsOf('A').map((r) => r.phoneme),
          ['/eɪ/', '/æ/', '/ɑː/', '/ɔː/', '/ə/']);
      expect(soundRowsOf('A').map((r) => r.kind), [
        LetterSoundKind.common,
        LetterSoundKind.common,
        LetterSoundKind.common,
        LetterSoundKind.common,
        LetterSoundKind.reduced,
      ]);
      expect(soundRowsOf('C').map((r) => r.kind),
          [LetterSoundKind.hard, LetterSoundKind.soft, LetterSoundKind.common]);
      expect(soundRowsOf('O').length, 6);
    });

    test('未收录的字母：抛错而不是给一张空表（数据错了要立刻看得见）', () {
      expect(() => soundRowsOf('Ä'), throwsStateError);
    });

    test('连播分组：26 组、按字母表顺序、字母名取首字符', () {
      expect(allLetterPlayGroups.length, 26);
      expect(allLetterPlayGroups.map((g) => g.cellKey), alphabetData.map((i) => i.char));
      expect(allLetterPlayGroups.map((g) => g.letterName),
          alphabetData.map((i) => i.char.substring(0, 1)));
      for (final group in allLetterPlayGroups) {
        expect(
          group.rows.map((r) =>
              [r.phoneme, r.kind, r.example, r.exampleIpa, r.hasAudio, r.note]),
          soundRowsOf(group.letterName).map((r) =>
              [r.phoneme, r.kind, r.example, r.exampleIpa, r.hasAudio, r.note]),
        );
      }
    });

    test('单字母连播分组：只有该字母那组', () {
      final group = letterPlayGroupOf('X');
      expect(group.cellKey, 'X x');
      expect(group.letterName, 'X');
      expect(group.rows.map((r) => r.phoneme), ['/ks/', '/gz/', '/z/']);
    });

  });

  group('音标录音（assets/phonetics/）', () {
    // 这组是「网格里每个音标都出得了声」的守门人：换录音包/改文件名后，
    // 一旦与 phonicsGroups 的 48 个符号对不上，这里直接红。
    final manifestFile = File('assets/phonetics/manifest.json');

    test('manifest.json 存在且覆盖全部 48 个音标（音标 + 例词两段录音）', () {
      expect(manifestFile.existsSync(), isTrue,
          reason: '缺 assets/phonetics/manifest.json——跑 tool/import-phonetics-audio.ts 生成');

      final clips = phonemeClipsFromManifest(manifestFile.readAsStringSync());
      final phones = phonicsGroups.expand((g) => g.items).map((i) => i.phone);
      for (final phone in phones) {
        final clip = clips[normalizePhone(phone)];
        expect(clip, isNotNull, reason: '音标 $phone 没有对应录音');
        expect(clip!.wordFile, isNotNull, reason: '音标 $phone 没有例词录音');
      }
    });

    test('录音里的例词与表格里的例词一致（换包没换表就是错读）', () {
      final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
      final keywordBySymbol = {
        for (final entry in (manifest['phonemes'] as List).cast<Map>())
          normalizePhone(entry['normalized'] as String): entry['keyword'] as String,
      };
      for (final item in phonicsGroups.expand((g) => g.items)) {
        expect(keywordBySymbol[normalizePhone(item.phone)], item.example,
            reason: '${item.phone} 的例词：录音里是 '
                '${keywordBySymbol[normalizePhone(item.phone)]}，表格里是 ${item.example}');
      }
    });

    test('manifest 里每个文件都真实存在（非空）', () {
      final clips = phonemeClipsFromManifest(manifestFile.readAsStringSync());
      expect(clips, isNotEmpty);
      for (final entry in clips.entries) {
        final names = [entry.value.file, if (entry.value.wordFile != null) entry.value.wordFile!];
        for (final name in names) {
          final f = File('assets/phonetics/$name');
          expect(f.existsSync(), isTrue, reason: '${entry.key} → $name 不在盘上');
          expect(f.lengthSync(), greaterThan(512), reason: '$name 内容可疑');
        }
      }
    });

    test('录音库不再有旧素材的残留文件', () {
      // 旧素材 v01..v20 / c01..c28（音标网 + Cambridge 那套）已整套换掉，
      // 残留只会在打包时白白增大体积
      final leftovers = Directory('assets/phonetics')
          .listSync()
          .map((e) => e.path.split('/').last)
          .where((n) => RegExp(r'^[vc]\d+\.mp3$').hasMatch(n));
      expect(leftovers, isEmpty, reason: '旧录音还在：${leftovers.join(' ')}');
    });
  });

  group('字母名取值', () {
    // 字母格的 TTS 文本由控制器按「字母名 → 例词」两段朗读（见
    // reference_controller_test），这里只守数据侧的取首字符规则。
    test('字母格取字符首字母（多字符字母也只有一个字母名）', () {
      const x = ReferenceCellData(
        char: 'X x',
        reading: '/eks/',
        example: 'X-ray',
        exampleIpa: '/ˈeksreɪ/',
        exampleCn: 'X光',
        isPhonetic: false,
      );
      expect(x.letterName, 'X');
    });
  });
}
