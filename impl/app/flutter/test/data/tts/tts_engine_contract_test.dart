import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// TtsEngine 抽象契约测试（用 fake 实现验证接口语义）。
///
/// 对照 Kotlin 端语义：
/// - speak 返回 utterance id（"ctx-N" / "ktk-N"），失败返回 null
/// - onSpeakingFinished 带结束的 utterance id（自然结束 / stop / 打断）
/// - stop 清理当前状态
/// - unavailabilityReason 提供具体原因

void main() {
  group('TtsEngine 契约', () {
    test('speak 返回自增 utterance id，失败返回 null', () {
      final engine = _FakeEngine();
      final id1 = engine.speak('hello');
      final id2 = engine.speak('world');
      expect(id1, isNotNull);
      expect(id2, isNotNull);
      expect(id1, isNot(id2));

      engine.failNextSpeak = true;
      expect(engine.speak('boom'), isNull);
    });

    test('onSpeakingFinished 收到结束的 utterance id', () async {
      final engine = _FakeEngine();
      final finished = <String?>[];
      engine.setOnSpeakingFinished(finished.add);

      final id = engine.speak('hello');
      engine.finish(id!);

      expect(finished, [id]);
    });

    test('stop 触发 onSpeakingFinished（带当前 id）', () async {
      final engine = _FakeEngine();
      final finished = <String?>[];
      engine.setOnSpeakingFinished(finished.add);

      final id = engine.speak('hello');
      engine.stop();

      expect(finished, [id]);
    });

    test('未注册回调时 stop 不抛异常', () {
      final engine = _FakeEngine();
      engine.speak('hello');
      engine.stop();
      expect(engine.isAvailable(), isTrue);
    });

    test('isAvailable / unavailabilityReason 反映引擎状态', () {
      final engine = _FakeEngine();
      expect(engine.isAvailable(), isTrue);
      expect(engine.unavailabilityReason(), isNull);

      engine.failureMessage = 'test failure';
      expect(engine.isAvailable(), isFalse);
      expect(engine.unavailabilityReason(), 'test failure');
    });

    test('切换监听器后旧回调不再收到事件', () {
      final engine = _FakeEngine();
      final first = <String?>[];
      final second = <String?>[];
      engine.setOnSpeakingFinished(first.add);
      final id = engine.speak('hello');
      engine.setOnSpeakingFinished(second.add);
      engine.finish(id!);

      expect(first, isEmpty);
      expect(second, [id]);
    });

    test('setOnSentenceStarted 收到句子位置（段索引 0 起，段内句序号 0 起）', () async {
      final engine = _FakeEngine();
      engine.setOnSentenceStarted((id, paragraphIndex, sentenceIndex, total) {});
      final id = engine.speak('hello');
      engine.simulateSentenceStarted(0, 1);
      expect(engine.lastParagraphIndex, 0);
      expect(engine.lastSentenceIndex, 1);
      expect(id, isNotNull);
    });
  });

  group('TtsSpeedMapper', () {
    test('Android：显示语速直接透传（setSpeechRate 以 1.0 为正常语速）', () {
      const mapper = SystemTtsSpeedMapper(isIos: false);
      expect(mapper.actualRate(1.0), 1.0);
      expect(mapper.actualRate(0.8), 0.8);
      expect(mapper.actualRate(1.2), 1.2);
    });

    test('iOS：按 AVSpeechUtterance 基准缩放（rate 0.5 = 正常语速）', () {
      const mapper = SystemTtsSpeedMapper(isIos: true);
      expect(mapper.actualRate(1.0), 0.5);
      expect(mapper.actualRate(0.8), closeTo(0.4, 1e-9));
      expect(mapper.actualRate(1.2), closeTo(0.6, 1e-9));
    });
  });
}

class _FakeEngine implements TtsEngine {
  int _counter = 0;
  String? currentId;
  bool failNextSpeak = false;
  String? failureMessage;
  void Function(String? utteranceId)? _callback;
  void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
      int total)? _sentenceStarted;
  int? lastParagraphIndex;
  int? lastSentenceIndex;

  @override
  bool isAvailable() => failureMessage == null;

  @override
  String? unavailabilityReason() => failureMessage;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    if (failNextSpeak) return null;
    currentId = 'ctx-${_counter++}';
    return currentId;
  }

  @override
  void stop() {
    final id = currentId;
    currentId = null;
    _callback?.call(id);
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    _callback = callback;
  }

  @override
  void setOnSentenceStarted(
      void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          callback) {
    _sentenceStarted = callback;
  }

  void simulateSentenceStarted(int paragraphIndex, int sentenceIndex) {
    _sentenceStarted?.call(currentId, paragraphIndex, sentenceIndex, 3);
    lastParagraphIndex = paragraphIndex;
    lastSentenceIndex = sentenceIndex;
  }

  void finish(String id) {
    if (currentId == id) currentId = null;
    _callback?.call(id);
  }
}
