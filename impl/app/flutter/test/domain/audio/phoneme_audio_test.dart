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

  group('phonemeFilesFromManifest', () {
    test('解析 normalized → file', () {
      const json = '''
      {
        "phonemes": [
          {"symbol": "i:", "normalized": "iː", "file": "v01.mp3"},
          {"symbol": "əU", "normalized": "əʊ", "file": "v17.mp3"}
        ]
      }''';
      final files = phonemeFilesFromManifest(json);
      expect(files, {'iː': 'v01.mp3', 'əʊ': 'v17.mp3'});
    });

    test('normalized 缺失时退回 symbol，键统一归一化', () {
      const json = '{"phonemes":[{"symbol":"/ɡ/","file":"c07.mp3"}]}';
      expect(phonemeFilesFromManifest(json), {'g': 'c07.mp3'});
    });

    test('坏 JSON / 结构不符 → 空表（页面回退例词，不抛）', () {
      expect(phonemeFilesFromManifest('not json'), isEmpty);
      expect(phonemeFilesFromManifest('{"phonemes":"oops"}'), isEmpty);
      expect(phonemeFilesFromManifest('{}'), isEmpty);
    });

    test('跳过无条件缺字段的条目', () {
      const json = '{"phonemes":[{"file":"a.mp3"},{"normalized":"x"},{"normalized":"y","file":"b.mp3"}]}';
      expect(phonemeFilesFromManifest(json), {'y': 'b.mp3'});
    });
  });
}
