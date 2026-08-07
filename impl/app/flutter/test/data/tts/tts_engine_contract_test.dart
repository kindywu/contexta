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
  });

  group('TtsSpeedMapper', () {
    const mapper = SystemTtsSpeedMapper();

    test('1x → 0.70，0.75x → 0.45（对照 Kotlin actualSpeechRate）', () {
      expect(mapper.actualRate(1.0), 0.70);
      expect(mapper.actualRate(0.75), 0.45);
    });
  });
}

class _FakeEngine implements TtsEngine {
  int _counter = 0;
  String? currentId;
  bool failNextSpeak = false;
  String? failureMessage;
  void Function(String? utteranceId)? _callback;

  @override
  bool isAvailable() => failureMessage == null;

  @override
  String? unavailabilityReason() => failureMessage;

  @override
  String? speak(String text, {double speed = 1.0}) {
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

  void finish(String id) {
    if (currentId == id) currentId = null;
    _callback?.call(id);
  }
}
