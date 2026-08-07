import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:kittentts/kittentts_flutter.dart' as kit;

/// KittenTTS 会话抽象：由 [KittenTtsFactory] 创建，测试注入 fake。
///
/// 职责：整段生成 WAV → audioplayers 播放 → 完成时回调 utterance id。
/// 每次 speak 打断上一次（生成 Job 取消 + 播放器 stop）。
abstract interface class KittenTtsSession {
  /// 生成并播放 [text]，结束后调用 finishListener。
  Future<void> speak(String text, {required double speed, required String utteranceId});

  /// 停止当前生成/播放（触发 finishListener）。
  Future<void> stop();

  /// 注册播放完成回调（自然结束 / stop / 被新 utterance 打断）。
  void setFinishListener(void Function(String utteranceId)? listener);

  Future<void> dispose();
}

/// KittenTTS 插件工厂（`KittenTTS.create` 的可注入包装）。
typedef KittenTtsFactory = Future<KittenTtsSession> Function({
  required String onnxPath,
  required String voicesPath,
});

/// 生产实现：KittenTTS 插件 + audioplayers 播放。
class KittenTtsPluginSession implements KittenTtsSession {
  KittenTtsPluginSession({required this._engine, required this._player});

  final kit.KittenTTS _engine;
  final AudioPlayer _player;
  void Function(String utteranceId)? _finishListener;
  String? _currentUtteranceId;
  Completer<void>? _playbackCompleter;
  StreamSubscription<void>? _completeSub;
  final _generationJobs = <Future<void>>[];

  /// 工厂实现：用内置 phonemizer 数据创建 KittenTTS。
  ///
  /// CEPhonemizer 需要 en_rules/en_list 数据文件；allowRuleBasedFallback
  /// 让离线环境可用（RuleBasedPhonemizer 兜底，无网络依赖）。
  static Future<KittenTtsSession> create({
    required String onnxPath,
    required String voicesPath,
  }) async {
    final instance = await kit.KittenTTS.create(
      config: kit.KittenTTSConfig(
        model: kit.model.micro,
        defaultVoice: kit.voice.bella,
        modelFiles: kit.KittenTTSModelFiles(
          onnxPath: onnxPath,
          voicesPath: voicesPath,
        ),
        phonemizer: kit.CEPhonemizer(allowRuleBasedFallback: true),
        analytics: false,
      ),
    );
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    return KittenTtsPluginSession(engine: instance, player: player);
  }

  @override
  Future<void> speak(
    String text, {
    required double speed,
    required String utteranceId,
  }) async {
    // 打断上一次（Kotlin QUEUE_FLUSH 语义）：取消旧生成 + 停旧播放
    await _stopCurrent();
    _currentUtteranceId = utteranceId;
    final job = _generateAndPlay(text, speed, utteranceId);
    _generationJobs.add(job);
    try {
      await job;
    } finally {
      _generationJobs.remove(job);
    }
  }

  Future<void> _generateAndPlay(
    String text,
    double speed,
    String utteranceId,
  ) async {
    try {
      final result = await _engine.generate(text, speed: speed);
      if (_currentUtteranceId != utteranceId) return; // 已被更新的 speak 打断
      final wav = result.wavData();
      await _playWav(wav, utteranceId);
    } catch (e) {
      // 生成失败：按引擎失败处理（完成回调照常触发，消费方按 id 清状态）
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    }
  }

  Future<void> _playWav(Uint8List wav, String utteranceId) async {
    _playbackCompleter = Completer<void>();
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) => _finishPlayback());
    try {
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
      await _playbackCompleter!.future;
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    } catch (_) {
      _finishPlayback();
      rethrow;
    }
  }

  void _finishPlayback() {
    final completer = _playbackCompleter;
    _playbackCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  Future<void> stop() async {
    await _stopCurrent();
  }

  Future<void> _stopCurrent() async {
    final id = _currentUtteranceId;
    _currentUtteranceId = null;
    _finishPlayback();
    try {
      await _player.stop();
    } catch (_) {}
    if (id != null) {
      _finishListener?.call(id);
    }
  }

  @override
  void setFinishListener(void Function(String utteranceId)? listener) {
    _finishListener = listener;
  }

  @override
  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _engine.dispose();
    await _player.dispose();
  }
}

/// KittenTTS 语速映射：插件 speed 即实际语速（0.5–2.0）。
class KittenSpeedMapper {
  const KittenSpeedMapper();

  double actualRate(double displaySpeed) => displaySpeed.clamp(0.5, 2.0);
}