import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reference/reference_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页 controller 测试（对照 Kotlin ReferenceViewModel）：
/// - speak 转发到 TTS 引擎
/// - 引擎初始化失败时静默（不抛出）

class _RecordingTts implements TtsEngine {
  final List<String> spoken = [];
  TtsVoice? lastVoice;

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    spoken.add(text);
    lastVoice = voice;
    return 'ctx-1';
  }

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnParagraphStarted(
      void Function(String? utteranceId, int paragraphIndex, int total)?
          callback) {}
}

void main() {
  test('speak 转发文本到引擎并携带音色', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      voice: () => TtsVoice.hugo,
    );

    await controller.speak('A. Apple');

    expect(tts.spoken, ['A. Apple']);
    expect(tts.lastVoice, TtsVoice.hugo);
  });

  test('speak 音色随注入值变化', () async {
    final tts = _RecordingTts();
    var voice = TtsVoice.bella;
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      voice: () => voice,
    );

    await controller.speak('A. Apple');
    expect(tts.lastVoice, TtsVoice.bella);

    voice = TtsVoice.luna;
    await controller.speak('B. Banana');
    expect(tts.lastVoice, TtsVoice.luna);
  });

  test('引擎初始化失败 → 静默跳过不抛出', () async {
    final controller = ReferenceController(
      ttsEngineFuture: Future.error(StateError('engine init failed')),
      voice: () => TtsVoice.bella,
    );

    await controller.speak('hello');

    expect(true, isTrue); // 到达此处即未抛出
  });
}
