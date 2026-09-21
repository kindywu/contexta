import 'dart:convert';

import 'package:contexta/domain/audio/phoneme_audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 音标录音映射的纯逻辑测试：符号归一化、manifest 解析、坏数据兜底。
/// 「manifest 是否覆盖 phonicsGroups 的 48 个音标」见
/// test/ui/reference/reference_data_test.dart（那里才有 48 个符号清单）。

void main() {
  group('normalizePhone', () {
    test('去掉包裹斜杠与空白', () {
      expect(normalizePhone('/iː/'), 'iː');
      expect(normalizePhone(' iː '), 'iː');
      expect(normalizePhone('/tʃ/'), 'tʃ');
    });

    test('ɡ(U+0261) 与 g(U+0067) 视为同一音素', () {
      expect(normalizePhone('/ɡ/'), 'g');
      expect(normalizePhone('/g/'), 'g');
    });
  });

  group('phonemeClipsFromManifest', () {
    test('解析 normalized → 音标 / 例词两段录音', () {
      const json = '''
      {
        "phonemes": [
          {"symbol": "iː", "normalized": "iː", "keyword": "see", "file": "s01.mp3", "wordFile": "w01.mp3"},
          {"symbol": "əʊ", "normalized": "əʊ", "keyword": "go", "file": "s16.mp3", "wordFile": "w16.mp3"}
        ]
      }''';
      final clips = phonemeClipsFromManifest(json);
      expect(clips['iː']?.file, 's01.mp3');
      expect(clips['iː']?.wordFile, 'w01.mp3');
      expect(clips['əʊ']?.file, 's16.mp3');
      expect(clips['əʊ']?.wordFile, 'w16.mp3');
    });

    test('normalized 缺失时退回 symbol，键统一归一化', () {
      const json = '{"phonemes":[{"symbol":"/ɡ/","file":"s26.mp3"}]}';
      final clips = phonemeClipsFromManifest(json);
      expect(clips.keys, ['g']);
      expect(clips['g']?.file, 's26.mp3');
      expect(clips['g']?.wordFile, isNull, reason: '没有 wordFile 就是 null（该例词回退 TTS）');
    });

    test('坏 JSON / 结构不符 → 空表（页面回退例词，不抛）', () {
      expect(phonemeClipsFromManifest('not json'), isEmpty);
      expect(phonemeClipsFromManifest('{"phonemes":"oops"}'), isEmpty);
      expect(phonemeClipsFromManifest('{}'), isEmpty);
    });

    test('跳过无条件缺字段的条目；wordFile 为空串按缺失处理', () {
      const json =
          '{"phonemes":[{"file":"a.mp3"},{"normalized":"x"},{"normalized":"y","file":"b.mp3","wordFile":""}]}';
      final clips = phonemeClipsFromManifest(json);
      expect(clips.keys, ['y']);
      expect(clips['y']?.wordFile, isNull);
    });
  });

  group('letterWords（字母读音行的例词录音）', () {
    test('解析符号 → 录音文件 + 词', () {
      final words = letterWordClipsFromManifest(jsonEncode({
        'letterWords': [
          {'phoneme': 'ks', 'word': 'box', 'file': 'l01.mp3'},
          {'phoneme': 'z', 'word': 'xylophone', 'file': 'l03.mp3'},
        ],
      }));

      expect(words.keys.toList()..sort(), ['ks', 'z']);
      expect(words['ks']?.file, 'l01.mp3');
      expect(words['ks']?.word, 'box');
      expect(words['z']?.word, 'xylophone');
    });

    test('符号同样过归一化（斜杠 / ɡ↔g）', () {
      final words = letterWordClipsFromManifest(jsonEncode({
        'letterWords': [
          {'phoneme': '/ɡ/', 'word': 'go', 'file': 'l09.mp3'},
        ],
      }));

      expect(words.keys, ['g'], reason: 'ɡ(U+0261) 归一到 g');
      expect(words['g']?.file, 'l09.mp3');
    });

    test('整段缺失（旧 manifest）：空表，不抛', () {
      expect(letterWordClipsFromManifest(jsonEncode({'phonemes': []})), isEmpty);
    });

    test('坏 JSON / 缺字段的条目：空表 / 跳过该条', () {
      expect(letterWordClipsFromManifest('{oops'), isEmpty);
      final words = letterWordClipsFromManifest(jsonEncode({
        'letterWords': [
          {'phoneme': 'ks'}, // 缺 word/file → 跳过
          {'phoneme': 'gz', 'word': 'exam', 'file': 'l02.mp3'},
        ],
      }));
      expect(words.keys, ['gz']);
    });
  });
}
