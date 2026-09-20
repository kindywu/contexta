import 'package:contexta/domain/audio/phoneme_audio.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reference/reference_controller.dart';
import 'package:contexta/ui/reference/reference_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页 controller 测试（对照 Kotlin ReferenceViewModel）：
/// - speak 转发到 TTS 引擎
/// - 引擎初始化失败时静默（不抛出）
/// - 音标格发音走录音（不经过 TTS），录音缺失才兜底读例词

class _RecordingTts implements TtsEngine {
  final List<String> spoken = [];
  final List<TtsVoice?> voices = [];
  TtsVoice? get lastVoice => voices.isEmpty ? null : voices.last;

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    spoken.add(text);
    voices.add(voice);
    return 'ctx-1';
  }

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnSentenceStarted(
      void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          callback) {}
}

/// 假录音库：记下播过哪些音标；`missing` 里的符号按「无录音」返回 false。
class _FakePhonemeAudio implements PhonemeAudio {
  _FakePhonemeAudio({this.missing = const {}});

  final Set<String> missing;
  final List<String> played = [];

  @override
  Future<bool> play(String phone) async {
    if (missing.contains(phone)) return false;
    played.add(phone);
    return true;
  }
}

const _phoneticCell = ReferenceCellData(
  char: '/iː/',
  reading: '单元音',
  example: 'see',
  exampleIpa: '/siː/',
  exampleCn: '',
  isPhonetic: true,
);

const _alphabetCell = ReferenceCellData(
  char: 'A a',
  reading: '/eɪ/',
  example: 'Apple',
  exampleIpa: '/ˈæpəl/',
  exampleCn: '苹果',
  isPhonetic: false,
);

void main() {
  test('speak 转发文本到引擎并携带音色', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      phonemeAudio: _FakePhonemeAudio(),
    );

    await controller.speak('A. Apple');

    expect(tts.spoken, ['A. Apple']);
  });

  test('音色固定 bella：不传就用默认值，且每次朗读都一样', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      phonemeAudio: _FakePhonemeAudio(),
    );

    await controller.speak('A. Apple');
    await controller.speak('B. Banana');

    expect(tts.voices, [TtsVoice.bella, TtsVoice.bella]);
  });

  test('音色可由构造参数指定（默认 bella 之外的取值）', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      phonemeAudio: _FakePhonemeAudio(),
      voice: TtsVoice.hugo,
    );

    await controller.speak('A. Apple');

    expect(tts.lastVoice, TtsVoice.hugo);
  });

  test('引擎初始化失败 → 静默跳过不抛出', () async {
    final controller = ReferenceController(
      ttsEngineFuture: Future.error(StateError('engine init failed')),
      phonemeAudio: _FakePhonemeAudio(),
    );

    await controller.speak('hello');

    expect(true, isTrue); // 到达此处即未抛出
  });

  group('音标格发音走录音（不走 TTS）', () {
    test('符号点击：放录音，TTS 不发声', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
      );

      await controller.playSymbol(_phoneticCell);

      expect(audio.played, ['/iː/']);
      expect(tts.spoken, isEmpty, reason: '音标发音不该经过 TTS');
    });

    test('符号点击：录音缺失才兜底读例词（不读 IPA）', () async {
      final tts = _RecordingTts();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: _FakePhonemeAudio(missing: {'/iː/'}),
      );

      await controller.playSymbol(_phoneticCell);

      expect(tts.spoken, ['see']);
    });

    test('发音按钮：先录音后例词，且送进 TTS 的只有例词', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      await controller.playCell(_phoneticCell);

      expect(audio.played, ['/iː/']);
      // 只有例词本身：不带 IPA、不带音标注脚、不拼成句子
      expect(tts.spoken, ['see']);
    });

    test('录音播完到例词之间留一拍（默认 1s）', () async {
      expect(ReferenceController.defaultPhonemeWordGap, const Duration(seconds: 1));

      final tts = _RecordingTts();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: _FakePhonemeAudio(),
        phonemeWordGap: const Duration(milliseconds: 120),
      );

      final sw = Stopwatch()..start();
      await controller.playCell(_phoneticCell);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100),
          reason: '例词应在录音后停顿一拍再开口');
      expect(tts.spoken, ['see']);
    });

    test('录音没放成就不白等：立刻读例词', () async {
      final tts = _RecordingTts();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: _FakePhonemeAudio(missing: {'/iː/'}),
        // 默认 1s；若实现无条件等待，这个用例会明显变慢（下面的耗时断言兜底）
        phonemeWordGap: const Duration(seconds: 1),
      );

      final sw = Stopwatch()..start();
      await controller.playCell(_phoneticCell);
      sw.stop();

      expect(tts.spoken, ['see']);
      expect(sw.elapsedMilliseconds, lessThan(500), reason: '没有录音就不该等那一拍');
    });

    test('字母格不受影响：仍是字母名 + 例词一段 TTS，不放录音', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
      );

      await controller.playSymbol(_alphabetCell);
      expect(tts.spoken, ['A']);
      expect(audio.played, isEmpty);

      await controller.playCell(_alphabetCell);
      expect(tts.spoken, ['A', 'A. Apple']);
      expect(audio.played, isEmpty);
    });
  });
}
