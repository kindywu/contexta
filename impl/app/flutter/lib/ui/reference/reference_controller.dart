import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/audio/phoneme_audio.dart';
import '../../domain/model/tts_voice.dart';
import '../../domain/tts/tts_engine.dart';
import 'reference_data.dart';

/// Reference 页控制器（对照 Kotlin ReferenceViewModel）：
/// 持 TTS 引擎（例词、字母名）+ 音标录音库，提供发音入口。
///
/// 音标本身的发音**不走 TTS**：TTS 读不出 IPA，只能拿近似英文拼写糊弄
/// （`/ɪ/` 读 "it"）。音标格改放随包录音（`assets/phonetics/`），TTS 只负责
/// 例词与字母名。
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
  });

  /// 录音播完到例词开口之间的停顿。不留这口气，两段会黏成一句。
  static const Duration defaultPhonemeWordGap = Duration(seconds: 1);

  final Future<TtsEngine> _ttsEngineFuture;
  final PhonemeAudio _phonemeAudio;
  final TtsVoice _voice;
  final Duration _phonemeWordGap;

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

  /// 「发音」按钮：字母格一段读完「字母名 + 例词」；音标格先放录音，
  /// **停一拍**（`_phonemeWordGap`）再读例词。
  ///
  /// 送进 TTS 的**只有例词本身**——不带音标符号、不带前缀后缀、不拼成句子。
  Future<void> playCell(ReferenceCellData cell) async {
    if (!cell.isPhonetic) {
      await speak(speakTextFor(cell));
      return;
    }
    final played = await _phonemeAudio.play(cell.char);
    // 录音没放成（符号不在库里/播放失败）就别白等一秒
    if (played) await Future<void>.delayed(_phonemeWordGap);
    await speak(cell.example);
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
