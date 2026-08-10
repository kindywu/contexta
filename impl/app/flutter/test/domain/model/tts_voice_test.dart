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
  });
}
