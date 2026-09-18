import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/model/tts_voice.dart';
import '../../domain/tts/tts_engine.dart';

/// 系统 TTS 引擎（flutter_tts）。两个平台走不同的初始化：
///
/// **Android**：对照 Kotlin TtsEngineImpl 的三重引擎回退链——
/// 1. com.xiaomi.mibrain.speech（小米内置）
/// 2. com.google.android.tts（Google TTS）
/// 3. 系统默认引擎
/// 初始化成功的第一个引擎被保留。HyperOS 上默认构造器可能发现不了内置引擎，
/// 显式包名逐个尝试（记忆：hyperos-tts-fix）。
///
/// **iOS**：flutter_tts 直接桥接 AVSpeechSynthesizer，没有「引擎包」概念
/// （`getEngines` / `setEngine` 在 iOS 侧无实现，探测必然失败），因此跳过
/// 候选链，只做共享音频会话 + 音频类别设置（否则静音开关会连朗读一起静音）。
///
/// 语速由 [SystemTtsSpeedMapper] 决定：Android 直接透传（1x→1.0），
/// iOS 按 AVSpeechUtterance 基准缩放（1x→0.5，见该类的对照表）。
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({
    FlutterTts? tts,
    this.engineCandidates = const [
      'com.xiaomi.mibrain.speech',
      'com.google.android.tts',
      null,
    ],
    TtsSpeedMapper? speedMapper,
    bool? isIos,
  })  : _tts = tts ?? FlutterTts(),
        _isIos = isIos ?? Platform.isIOS,
        speedMapper = speedMapper ?? SystemTtsSpeedMapper(isIos: isIos) {
    _wireCallbacks();
  }

  final FlutterTts _tts;
  final List<String?> engineCandidates;
  final TtsSpeedMapper speedMapper;

  /// 是否按 iOS 语义初始化（测试注入；null → 按运行平台判定，见构造器）。
  final bool _isIos;

  bool _ready = false;
  String? _failureMessage;
  String? _pendingText;
  void Function(String? utteranceId)? _onSpeakingFinished;
  int _utteranceCounter = 0;

  /// 逐个尝试引擎候选，第一个初始化成功的保留（对照 Kotlin tryEngines）。
  /// iOS 无候选链，走 [_initIos]。
  Future<void> init() async {
    if (_isIos) {
      await _initIos();
      return;
    }
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

  /// iOS 初始化：共享音频会话 + playback 类别（静音开关不静音朗读、
  /// 压低其他 App 音量而不打断），再确认 en-US 语音可用（系统未下载语音时
  /// AVAudioSynthesizer 会「成功」但不出声，这里显式判失败以便上层给出提示）。
  Future<void> _initIos() async {
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      if (!await _tts.isLanguageAvailable('en-US')) {
        _failureMessage = 'iOS 系统未安装 en-US 语音';
        return;
      }
      _ready = true;
      final pending = _pendingText;
      _pendingText = null;
      if (pending != null) {
        _tts.speak(pending);
      }
    } catch (e) {
      _failureMessage = 'iOS 系统 TTS 初始化失败：$e';
    }
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
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
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

  @override
  void setOnSentenceStarted(
      void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          callback) {
    // 拼接朗读无句子边界，不实现（对照 Kotlin 无对应机制）
  }
}
