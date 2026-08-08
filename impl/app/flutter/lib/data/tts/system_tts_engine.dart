import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/tts/tts_engine.dart';

/// 系统 TTS 引擎（flutter_tts），对照 Kotlin TtsEngineImpl 的三重引擎回退链：
/// 1. com.xiaomi.mibrain.speech（小米内置）
/// 2. com.google.android.tts（Google TTS）
/// 3. 系统默认引擎
///
/// 初始化成功的第一个引擎被保留。HyperOS 上默认构造器可能发现不了内置引擎，
/// 显式包名逐个尝试（记忆：hyperos-tts-fix）。语速由 [SystemTtsSpeedMapper]
/// 决定：显示语速直接透传（1x→1.0、0.75x→0.75）。
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({
    FlutterTts? tts,
    this.engineCandidates = const [
      'com.xiaomi.mibrain.speech',
      'com.google.android.tts',
      null,
    ],
    this.speedMapper = const SystemTtsSpeedMapper(),
  }) : _tts = tts ?? FlutterTts() {
    _wireCallbacks();
  }

  final FlutterTts _tts;
  final List<String?> engineCandidates;
  final TtsSpeedMapper speedMapper;

  bool _ready = false;
  String? _failureMessage;
  String? _pendingText;
  void Function(String? utteranceId)? _onSpeakingFinished;
  int _utteranceCounter = 0;

  /// 逐个尝试引擎候选，第一个初始化成功的保留（对照 Kotlin tryEngines）。
  Future<void> init() async {
    for (var i = 0; i < engineCandidates.length; i++) {
      final pkg = engineCandidates[i];
      try {
        final ok = await _tryEngine(pkg);
        if (ok) return;
      } catch (_) {
        // 引擎包不存在或初始化抛错 → 尝试下一个
      }
    }
    _failureMessage = 'No TTS engine could be initialized';
  }

  Future<bool> _tryEngine(String? pkg) async {
    if (pkg != null) {
      final installed = await _isEngineInstalled(pkg);
      if (!installed) return false;
      try {
        await _tts.setEngine(pkg);
      } catch (_) {
        return false;
      }
    }
    // setEngine 完成 = 引擎初始化成功（插件 onInitListenerWithCallback 在
    // SUCCESS 时 success(1)，失败时 error 抛 PlatformException）。
    // 再做一次语言探测：引擎能识别 en 才算真正可用（对照 Kotlin onInit
    // SUCCESS 后设置 Locale.ENGLISH）。
    if (pkg == null) {
      try {
        if (!await _tts.isLanguageAvailable('en-US')) return false;
      } catch (_) {
        return false;
      }
    }
    _ready = true;
    // 初始化期间的 speak 被暂存，引擎就绪后补播（对照 Kotlin TtsEngineImpl）
    final pending = _pendingText;
    _pendingText = null;
    if (pending != null) {
      _tts.speak(pending);
    }
    return true;
  }

  Future<bool> _isEngineInstalled(String pkg) async {
    try {
      final engines = await _tts.getEngines;
      if (engines is! List) return false;
      return engines.any((e) => e == pkg);
    } catch (_) {
      return false;
    }
  }

  void _wireCallbacks() {
    _tts.setStartHandler(() {
      _pendingText = null;
    });
    _tts.setCompletionHandler(() => _finishCurrent());
    _tts.setErrorHandler((_) => _finishCurrent());
    _tts.setCancelHandler(_finishCurrent);
  }

  /// 完成/错误/取消/停止统一出口：带当前 utterance id 通知一次，并清空
  /// 当前 id，防止迟到回调重复通知（对照 Kotlin UtteranceProgressListener：
  /// onDone/onError/onStop → notifySpeakingFinished）。
  void _finishCurrent() {
    final id = _currentUtteranceId;
    _currentUtteranceId = null;
    if (id != null) {
      _onSpeakingFinished?.call(id);
    }
  }

  String? _currentUtteranceId;

  @override
  bool isAvailable() => _ready;

  @override
  String? unavailabilityReason() => _failureMessage;

  @override
  String? speak(String text, {double speed = 1.0}) {
    if (_ready) {
      final id = 'ctx-${_utteranceCounter++}';
      _currentUtteranceId = id;
      final rate = speedMapper.actualRate(speed);
      try {
        _tts.setSpeechRate(rate);
        _tts.setLanguage('en');
        _tts.speak(text);
        return id;
      } catch (_) {
        _currentUtteranceId = null;
        return null;
      }
    }
    if (_failureMessage == null) {
      _pendingText = text; // 初始化中：暂存，init 完成后播放（对照 Kotlin）
    }
    return null;
  }

  @override
  void stop() {
    try {
      _tts.stop();
    } catch (_) {}
    // 引擎侧 onStop 回调会带被打断的 utterance id 通知（对照 Kotlin）
    _finishCurrent();
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    _onSpeakingFinished = callback;
  }
}
