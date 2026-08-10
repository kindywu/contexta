import 'package:contexta/data/tts/system_tts_engine.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';

/// SystemTtsEngine 测试：引擎回退链路由 + 语速映射 + 回调语义。
///
/// 对照 Kotlin TtsEngineImpl：
/// - 引擎候选依次尝试，第一个初始化成功的保留
/// - speak 返回 "ctx-N"，失败返回 null
/// - completion/error/cancel handler → onSpeakingFinished
/// - 语速：显示语速直接透传（1x→1.0、0.75x→0.75，SystemTtsSpeedMapper）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemTtsEngine', () {
    test('按候选顺序尝试引擎，第一个安装的引擎被选中', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);

      await engine.init();

      expect(engine.isAvailable(), isTrue);
      expect(tts.setEngineCalls, ['com.google.android.tts']);
    });

    test('小米引擎已安装时优先选中', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.xiaomi.mibrain.speech', 'com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);

      await engine.init();

      expect(engine.isAvailable(), isTrue);
      expect(tts.setEngineCalls, ['com.xiaomi.mibrain.speech']);
    });

    test('显式引擎均未安装时用系统默认', () async {
      final tts = _RecorderFlutterTts(installedEngines: const []);
      final engine = SystemTtsEngine(tts: tts);

      await engine.init();

      expect(engine.isAvailable(), isTrue);
      expect(tts.setEngineCalls, isEmpty); // 未调 setEngine，走默认
      expect(tts.languageProbes, ['en-US']); // 语言探测确认引擎可用
    });

    test('所有引擎尝试失败后不可用并记录原因', () async {
      final tts = _ThrowingFlutterTts();
      final engine = SystemTtsEngine(tts: tts);

      await engine.init();

      expect(engine.isAvailable(), isFalse);
      expect(engine.unavailabilityReason(), 'No TTS engine could be initialized');
    });

    test('speak 返回自增 ctx id，语速按映射设置', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);
      await engine.init();

      final id1 = engine.speak('hello', speed: 1.0);
      final id2 = engine.speak('world', speed: 0.75);

      expect(id1, 'ctx-0');
      expect(id2, 'ctx-1');
      expect(tts.speechRates, [1.0, 0.75]);
      expect(tts.spokenTexts, ['hello', 'world']);
    });

    test('完成回调 → onSpeakingFinished 带当前 id', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);
      await engine.init();
      final finished = <String?>[];
      engine.setOnSpeakingFinished(finished.add);

      final id = engine.speak('hello')!;
      tts.fireCompletion();

      expect(finished, [id]);
    });

    test('错误回调 → onSpeakingFinished 带当前 id', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);
      await engine.init();
      final finished = <String?>[];
      engine.setOnSpeakingFinished(finished.add);

      final id = engine.speak('hello')!;
      tts.fireError();

      expect(finished, [id]);
    });

    test('stop 触发 onSpeakingFinished（被打断的 utterance）', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);
      await engine.init();
      final finished = <String?>[];
      engine.setOnSpeakingFinished(finished.add);

      final id = engine.speak('hello')!;
      engine.stop();
      tts.fireError(); // 迟到的引擎回调：id 已清空，不再重复通知

      expect(finished, [id]);
    });

    test('不可用时 speak 返回 null 且暂存，引擎就绪后补播', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);

      expect(engine.speak('early'), isNull);
      expect(tts.spokenTexts, isEmpty);

      await engine.init();

      expect(engine.isAvailable(), isTrue);
      expect(tts.spokenTexts, ['early']);
    });

    test('setSpeechRate/setLanguage 每次 speak 前设置', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);
      await engine.init();

      engine.speak('hello');

      expect(tts.languageCalls, ['en']);
    });

    test('voice 参数被忽略，不影响朗读', () async {
      final tts = _RecorderFlutterTts(
        installedEngines: ['com.google.android.tts'],
      );
      final engine = SystemTtsEngine(tts: tts);
      await engine.init();

      final id = engine.speak('hello', voice: TtsVoice.hugo);

      expect(id, 'ctx-0');
      // 与不带 voice 时行为一致（fake 记录的朗读文本相同）
      expect(tts.spokenTexts, ['hello']);
    });
  });
}

class _RecorderFlutterTts extends FlutterTts {
  _RecorderFlutterTts({required this.installedEngines});

  final List<String> installedEngines;
  final List<String> setEngineCalls = [];
  final List<double> speechRates = [];
  final List<String> spokenTexts = [];
  final List<String> languageCalls = [];
  final List<String> languageProbes = [];
  VoidCallback? _completion;
  VoidCallback? _error;
  VoidCallback? _cancel;

  @override
  Future<dynamic> get getEngines async => installedEngines;

  @override
  Future<dynamic> isLanguageAvailable(String language) async {
    languageProbes.add(language);
    return true;
  }

  @override
  Future<dynamic> setEngine(String engine) async {
    setEngineCalls.add(engine);
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    languageCalls.add(language);
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    speechRates.add(rate);
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spokenTexts.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;

  @override
  void setCompletionHandler(VoidCallback callback) {
    _completion = callback;
  }

  @override
  void setErrorHandler(ErrorHandler handler) {
    _error = () => handler('test error');
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    _cancel = callback;
  }

  void fireCompletion() => _completion?.call();
  void fireError() => _error?.call();
  void fireCancel() => _cancel?.call();
}

class _ThrowingFlutterTts extends FlutterTts {
  _ThrowingFlutterTts();

  @override
  Future<dynamic> get getEngines async => const [];

  @override
  Future<dynamic> isLanguageAvailable(String language) async => false;

  @override
  Future<dynamic> setEngine(String engine) async {
    throw StateError('engine unavailable');
  }

  @override
  Future<dynamic> setLanguage(String language) async => 0;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 0;

  @override
  Future<dynamic> stop() async => 0;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => 0;
}
