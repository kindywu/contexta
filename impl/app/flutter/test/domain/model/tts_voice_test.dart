import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/domain/model/tts_voice.dart';

void main() {
  group('TtsVoice', () {
    test('dbValue round-trip：8 个音色均可解析', () {
      for (final v in TtsVoice.values) {
        expect(TtsVoice.fromDbValue(v.dbValue), v);
      }
    });

    test('dbValue 为大写枚举名，sdkVoiceId 为小写名', () {
      expect(TtsVoice.bella.dbValue, 'BELLA');
      expect(TtsVoice.bella.sdkVoiceId, 'bella');
      expect(TtsVoice.hugo.dbValue, 'HUGO');
      expect(TtsVoice.hugo.sdkVoiceId, 'hugo');
    });

    test('未知 dbValue 抛 ArgumentError', () {
      expect(() => TtsVoice.fromDbValue('UNKNOWN'), throwsArgumentError);
    });

    test('性别与标签正确', () {
      expect(TtsVoice.bella.isFemale, isTrue);
      expect(TtsVoice.jasper.isFemale, isFalse);
      expect(TtsVoice.bella.label, '贝拉 · Bella');
      expect(TtsVoice.bella.englishName, 'Bella');
      expect(TtsVoice.leo.label, '莱奥 · Leo');
    });

    test('pickRandom 只产出 8 个内置音色，且男女不限', () {
      final random = Random(1);
      final picked = {for (var i = 0; i < 200; i++) TtsVoice.pickRandom(random)};
      expect(picked.difference(TtsVoice.values.toSet()), isEmpty);
      // 200 次抽样必然覆盖两性（8 个音色等概率，漏掉任一侧的概率可忽略）
      expect(picked.any((v) => v.isFemale), isTrue);
      expect(picked.any((v) => !v.isFemale), isTrue);
    });

    test('tryFromDbValue：null / 未知值返回 null，合法值等价 fromDbValue', () {
      expect(TtsVoice.tryFromDbValue(null), isNull);
      expect(TtsVoice.tryFromDbValue('UNKNOWN'), isNull);
      expect(TtsVoice.tryFromDbValue('HUGO'), TtsVoice.hugo);
    });
  });

  group('TtsVoiceSetting', () {
    test('随机：dbValue 为 RANDOM 哨兵，label「随机」', () {
      const setting = TtsVoiceSetting.random();
      expect(setting.isRandom, isTrue);
      expect(setting.voice, isNull);
      expect(setting.dbValue, 'RANDOM');
      expect(setting.label, '随机');
    });

    test('固定：dbValue / label 取具体音色', () {
      const setting = TtsVoiceSetting.fixed(TtsVoice.luna);
      expect(setting.isRandom, isFalse);
      expect(setting.voice, TtsVoice.luna);
      expect(setting.dbValue, 'LUNA');
      expect(setting.label, '露娜 · Luna');
    });

    test('fromDbValue：RANDOM / 具体音色 / 未知值抛错', () {
      expect(TtsVoiceSetting.fromDbValue('RANDOM'), const TtsVoiceSetting.random());
      expect(TtsVoiceSetting.fromDbValue('KIKI'),
          const TtsVoiceSetting.fixed(TtsVoice.kiki));
      expect(() => TtsVoiceSetting.fromDbValue('UNKNOWN'), throwsArgumentError);
    });

    test('相等性按音色值（随机 = 随机）', () {
      expect(const TtsVoiceSetting.random(), const TtsVoiceSetting.random());
      expect(const TtsVoiceSetting.fixed(TtsVoice.leo),
          const TtsVoiceSetting.fixed(TtsVoice.leo));
      expect(const TtsVoiceSetting.fixed(TtsVoice.leo),
          isNot(const TtsVoiceSetting.random()));
    });
  });
}
