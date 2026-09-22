import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/audio/phoneme_audio.dart';

/// 播放一段音频。抽成接口是为了能测「平台不上报播放完成」这类路径——
/// audioplayers 的 `AudioPlayer` 依赖平台通道，单测里起不来。
abstract class ClipPlayer {
  /// 播放 asset（路径相对 `assets/`）。正常返回 = **已开始**播放。
  Future<void> play(String assetPath);

  /// 停止当前播放（下一次 play 前调用）。
  Future<void> stop();

  /// 当前播放结束。平台侧不上报时由调用方 `timeout` 兜底。
  Future<void> get onComplete;
}

/// 生产实现：audioplayers。
class AudioPlayersClipPlayer implements ClipPlayer {
  AudioPlayersClipPlayer([AudioPlayer? player]) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(String assetPath) => _player.play(AssetSource(assetPath));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> get onComplete => _player.onPlayerComplete.first;
}

/// 随包分发的音标录音播放器（`assets/phonetics/`，48 个音标 + 48 个例词）。
///
/// 映射表从 `assets/phonetics/manifest.json` 读（导入脚本生成，符号 → 录音文件名），
/// 首次播放时懒加载一次并缓存；文件名不硬编码在这里——加/换录音只改 manifest。
class AssetPhonemeAudio implements PhonemeAudio {
  AssetPhonemeAudio({
    AssetBundle? bundle,
    ClipPlayer? player,
    this.manifestPath = 'assets/phonetics/manifest.json',
    this.assetDir = 'phonetics',
  })  : _bundle = bundle ?? rootBundle,
        _player = player ?? AudioPlayersClipPlayer();

  /// 播放结束时等多久算「播完了」。正常录音约 1.5s；超时按播放结束处理，
  /// 避免平台侧不上报时把后续 TTS 卡住。
  static const Duration _playTimeout = Duration(seconds: 5);

  final AssetBundle _bundle;
  final ClipPlayer _player;
  final String manifestPath;

  /// 传给 `AssetSource` 的目录（相对 `assets/`，audioplayers 自带这个前缀）。
  final String assetDir;

  Future<Map<String, PhonemeClip>>? _clips;
  Future<Map<String, LetterWordClip>>? _letterWords;

  @override
  Future<bool> play(String phone) => _play(phone, '音标', (c) => c.file);

  @override
  Future<bool> playWord(String phone) => _play(phone, '例词', (c) => c.wordFile);

  @override
  Future<bool> playLetterWord(String letter, String phone) async {
    final words = await (_letterWords ??= _loadLetterWords());
    final clip = words[letterWordKey(letter, phone)];
    if (clip == null) {
      debugPrint('[PhonemeAudio] $letter 的 $phone 没有例词录音（库内 ${words.length} 条）→ 回退 TTS');
      return false;
    }
    return _playFile(phone, '字母读音行例词', clip.file);
  }

  @override
  Future<void> stop() => _player.stop();

  /// 播放 [phone] 的某一段录音（[pick] 决定取音标还是例词那一段）。
  Future<bool> _play(
    String phone,
    String kind,
    String? Function(PhonemeClip) pick,
  ) async {
    final clips = await (_clips ??= _loadClips());
    final clip = clips[normalizePhone(phone)];
    final file = clip == null ? null : pick(clip);
    if (file == null) {
      debugPrint('[PhonemeAudio] $phone 没有$kind录音（库内 ${clips.length} 条）→ 回退例词 TTS');
      return false;
    }
    return _playFile(phone, kind, file);
  }

  /// 播一个已解析出来的文件名，等播完（供「先读音后例词」的连读排序）。
  Future<bool> _playFile(String phone, String kind, String file) async {
    try {
      await _player.stop();
      await _player.play('$assetDir/$file');
    } catch (e) {
      // 播放没能启动才算失败（调用方走兜底）。这里必须留日志——
      // 否则「音标走了 TTS」在真机上完全静默（2026-09-20 排查过一次）
      debugPrint('[PhonemeAudio] $phone 的$kind录音播放失败 → 回退例词 TTS: $e');
      return false;
    }

    // 等播完（供「先音标后例词」的连读排序）。**已开始播放就不再算失败**：
    // 平台侧不上报完成只影响与后续录音的间隔，不该把播过的音判成没播。
    try {
      await _player.onComplete.timeout(_playTimeout);
    } on TimeoutException {
      debugPrint('[PhonemeAudio] $phone 的$kind录音完成事件未上报（${_playTimeout.inSeconds}s 超时），按播完继续');
    } catch (e) {
      debugPrint('[PhonemeAudio] $phone 的$kind录音结束事件异常，按播完继续: $e');
    }
    return true;
  }

  Future<Map<String, PhonemeClip>> _loadClips() async {
    try {
      final loaded = phonemeClipsFromManifest(await _bundle.loadString(manifestPath));
      debugPrint('[PhonemeAudio] 录音库载入 ${loaded.length} 条');
      return loaded;
    } catch (e) {
      debugPrint('[PhonemeAudio] 录音库载入失败（$manifestPath）: $e');
      return const {}; // manifest 缺失/损坏：全部符号按「无录音」处理
    }
  }

  Future<Map<String, LetterWordClip>> _loadLetterWords() async {
    try {
      final loaded =
          letterWordClipsFromManifest(await _bundle.loadString(manifestPath));
      debugPrint('[PhonemeAudio] 字母读音行例词录音载入 ${loaded.length} 条');
      return loaded;
    } catch (e) {
      debugPrint('[PhonemeAudio] 字母读音行例词录音载入失败（$manifestPath）: $e');
      return const {};
    }
  }
}
