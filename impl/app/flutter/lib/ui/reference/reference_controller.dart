import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/audio/phoneme_audio.dart';
import '../../domain/model/tts_voice.dart';
import '../../domain/tts/tts_engine.dart';
import 'reference_data.dart';

/// Reference 页控制器（对照 Kotlin ReferenceViewModel）：
/// 持 TTS 引擎（字母名）+ 音标录音库（音标本身 + 例词），提供发音入口。
///
/// 音标格的两段发音都**优先走随包录音**（`assets/phonetics/`）：音标本身 TTS 读不出
/// （IPA 符号），例词录音则是同一套人声、比 TTS 更像「跟着表读」。录音缺了才回退
/// TTS 读例词——TTS 只负责字母名与兜底例词。
///
/// **音色固定 bella**（不跟随设置页的全局音色）：参考页是「对着表一个个听」的
/// 场景，字母表与音标前后切换时音色必须一致，否则每换一格就换个嗓子；
/// 阅读页/词汇页仍跟随全局设置。
class ReferenceController {
  ReferenceController({
    required this._ttsEngineFuture,
    required this._phonemeAudio,
    this._voice = TtsVoice.bella,
    this._phonemeWordGap = defaultPhonemeWordGap,
    this._groupGap = defaultGroupGap,
  });

  /// 录音播完到例词开口之间的停顿。不留这口气，两段会黏成一句。
  static const Duration defaultPhonemeWordGap = Duration(seconds: 1);

  /// 连播时组与组之间的额外停顿（组内格子紧挨着读，换组才歇一口气）。
  static const Duration defaultGroupGap = Duration(seconds: 1);

  final Future<TtsEngine> _ttsEngineFuture;
  final PhonemeAudio _phonemeAudio;
  final TtsVoice _voice;
  final Duration _phonemeWordGap;
  final Duration _groupGap;

  /// 连播轮次令牌：`playSequence` / `stopSequence` 各推进一步，
  /// 循环与格内各段靠它判断本轮是否已被打断（旧轮次的回声一律丢弃）。
  int _sequenceToken = 0;

  /// 朗读文本（引擎未就绪时静默跳过，与页面其它 TTS 消费方一致）。
  Future<void> speak(String text) async {
    try {
      final engine = await _ttsEngineFuture;
      engine.speak(text, voice: _voice);
    } catch (_) {
      // 引擎初始化失败：不打断页面交互
    }
  }

  /// 符号点击：字母格读字母名；音标格放录音。
  ///
  /// 录音缺失（符号不在库里/播放失败）时兜底读例词——**绝不把 IPA 原文送进 TTS**。
  Future<void> playSymbol(ReferenceCellData cell) async {
    if (!cell.isPhonetic) {
      await speak(cell.char.substring(0, 1));
      return;
    }
    if (!await _phonemeAudio.play(cell.char)) await speak(cell.example);
  }

  /// 例词点击：音标格放例词录音，录音缺失才回退 TTS 读例词；字母格一直走 TTS。
  Future<void> playExample(ReferenceCellData cell) async {
    if (!cell.isPhonetic) {
      await speak(cell.example);
      return;
    }
    if (!await _phonemeAudio.playWord(cell.char)) await speak(cell.example);
  }

  /// 「发音」按钮：字母格一段读完「字母名 + 例词」；音标格按顺序读
  /// **音标录音 → 停一拍（`_phonemeWordGap`）→ 例词录音**。
  ///
  /// 送进 TTS 的**只有例词本身**——不带音标符号、不带前缀后缀、不拼成句子。
  Future<void> playCell(ReferenceCellData cell) => _playCell(cell, null);

  Future<void> _playCell(
    ReferenceCellData cell,
    bool Function()? aborted,
  ) async {
    if (!cell.isPhonetic) {
      await speak(speakTextFor(cell));
      return;
    }
    final played = await _phonemeAudio.play(cell.char);
    if (aborted?.call() ?? false) return;
    // 录音没放成（符号不在库里/播放失败）就别白等一秒
    if (played) await Future<void>.delayed(_phonemeWordGap);
    if (aborted?.call() ?? false) return;
    await playExample(cell);
  }

  /// 连播 [groups]：组内逐个走一遍「音标录音 → 停一拍 → 例词录音」，
  /// **组与组之间再停一拍**（`_groupGap`，让「换了一组」听得出来）。
  ///
  /// 传 `[cellsOf(group)]` 就是只播一组（没有组边界，自然不额外停）。
  /// [onCell] 在每个音标**开播前**回调（组间那一拍走完之后），
  /// UI 用它高亮并滚动到当前格。
  ///
  /// 中途 [stopSequence] 或新开一轮会打断本轮——立刻掐声，**且当前这一格不再
  /// 往下读**（否则「停止」后还会冒出一句例词；录音被 `stop()` 掐掉时等播完的
  /// 那一拍要么立刻返回、要么 5s 超时放行，只看令牌判断）。
  Future<void> playSequence(
    List<List<ReferenceCellData>> groups, {
    void Function(ReferenceCellData cell)? onCell,
  }) async {
    final token = ++_sequenceToken;
    for (final (index, cells) in groups.indexed) {
      if (token != _sequenceToken) return;
      if (index > 0) {
        await Future<void>.delayed(_groupGap);
        if (token != _sequenceToken) return;
      }
      for (final cell in cells) {
        if (token != _sequenceToken) return;
        onCell?.call(cell);
        await _playCell(cell, () => token != _sequenceToken);
      }
    }
  }

  /// 停止连播：掐掉当前声音，本轮循环随即退出。单格点播不受影响。
  Future<void> stopSequence() async {
    _sequenceToken++;
    await _phonemeAudio.stop();
  }
}

/// Reference 页控制器 Provider（TTS 引擎单例，跨页面共享）。
///
/// 音色**不读设置**：参考页固定 `TtsVoice.bella`（见类文档）。所以这里也就不用
/// 像词汇页那样用 `ref.read` 每次取当前音色——固定值没有「重建窗口期取到旧值」
/// 的问题。设置页换音色对参考页无影响。
final referenceControllerProvider = Provider<ReferenceController>((ref) {
  return ReferenceController(
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
    phonemeAudio: ref.watch(phonemeAudioProvider),
  );
});
