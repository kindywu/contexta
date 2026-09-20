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

/// 随包分发的音标录音播放器（`assets/phonetics/`，48 个音标，共约 1.1MB）。
///
/// 映射表从 `assets/phonetics/manifest.json` 读（抓取脚本生成，符号 → 文件名），
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

  Future<Map<String, String>>? _files;

  @override
  Future<bool> play(String phone) async {
    final files = await (_files ??= _loadFiles());
    final file = files[normalizePhone(phone)];
    if (file == null) {
      debugPrint('[PhonemeAudio] $phone 不在录音库（库内 ${files.length} 条）→ 回退例词 TTS');
      return false;
    }

    try {
      await _player.stop();
      await _player.play('$assetDir/$file');
    } catch (e) {
      // 播放没能启动才算失败（调用方走例词兜底）。这里必须留日志——
      // 否则「音标走了 TTS」在真机上完全静默（2026-09-20 排查过一次）
      debugPrint('[PhonemeAudio] $phone 播放失败 → 回退例词 TTS: $e');
      return false;
    }

    // 等播完（供「先音标后例词」的连读排序）。**已开始播放就不再算失败**：
    // 平台侧不上报完成只影响与后续 TTS 的间隔，不该把播过的音判成没播。
    try {
      await _player.onComplete.timeout(_playTimeout);
    } on TimeoutException {
      debugPrint('[PhonemeAudio] $phone 播放完成事件未上报（${_playTimeout.inSeconds}s 超时），按播完继续');
    } catch (e) {
      debugPrint('[PhonemeAudio] $phone 播放结束事件异常，按播完继续: $e');
    }
    return true;
  }

  Future<Map<String, String>> _loadFiles() async {
    try {
      final loaded = phonemeFilesFromManifest(await _bundle.loadString(manifestPath));
      debugPrint('[PhonemeAudio] 录音库载入 ${loaded.length} 条');
      return loaded;
    } catch (e) {
      debugPrint('[PhonemeAudio] 录音库载入失败（$manifestPath）: $e');
      return const {}; // manifest 缺失/损坏：全部符号按「无录音」处理
    }
  }
}
