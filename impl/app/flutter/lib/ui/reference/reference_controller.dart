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

  /// 「发音」按钮：字母格读 **字母名 → 停一拍（`_phonemeWordGap`）→ 例词**
  /// （两段 TTS）；音标格读 **音标录音 → 停一拍 → 例词录音**。两边同款节奏。
  ///
  /// 送进 TTS 的**只有字母名与例词本身**——不带音标符号、不带前缀后缀、不拼成句子。
  Future<void> playCell(ReferenceCellData cell) => _playCell(cell, null);

  Future<void> _playCell(
    ReferenceCellData cell,
    bool Function()? aborted,
  ) async {
    if (!cell.isPhonetic) {
      await speak(cell.letterName);
      if (aborted?.call() ?? false) return;
      await Future<void>.delayed(_phonemeWordGap);
      if (aborted?.call() ?? false) return;
      await speak(cell.example);
      return;
    }
    final played = await _phonemeAudio.play(cell.char);
    if (aborted?.call() ?? false) return;
    // 录音没放成（符号不在库里/播放失败）就别白等一秒
    if (played) await Future<void>.delayed(_phonemeWordGap);
    if (aborted?.call() ?? false) return;
    await playExample(cell);
  }

  /// 读音行点**读音**：放这个读音本身的录音；没有录音（X 的 `/ks/` `/gz/`）
  /// 兜底读例词——IPA 绝不进 TTS。
  Future<void> playLetterSound(LetterSoundRow row) async {
    if (!row.hasAudio) {
      await speak(row.example);
      return;
    }
    if (!await _phonemeAudio.play(row.phoneme)) await speak(row.example);
  }

  /// 读音行点**例词**：放这条例词的录音（自带例词的行走 TTS 预生成的
  /// `letterWords` 那批），录音缺了回退 TTS 读例词。
  Future<void> playLetterExample(LetterSoundRow row) async {
    final played = row.isOwnExample
        ? await _phonemeAudio.playLetterWord(row.phoneme)
        : await _phonemeAudio.playWord(row.phoneme);
    if (!played) await speak(row.example);
  }

  /// 连播里的一行：**读音录音 → 停一拍（`_phonemeWordGap`）→ 例词录音**，
  /// 与音标格「发音」同款节奏（字母读音复用的就是那 48 个音标录音）。
  /// 没有录音的那一段就跳过、也不白等那一拍。
  Future<void> _playLetterRow(
    LetterSoundRow row,
    bool Function()? aborted,
  ) async {
    if (aborted?.call() ?? false) return;
    if (row.hasAudio && await _phonemeAudio.play(row.phoneme)) {
      if (aborted?.call() ?? false) return;
      await Future<void>.delayed(_phonemeWordGap);
      if (aborted?.call() ?? false) return;
    }
    await playLetterExample(row);
  }

  /// 字母连播 [groups]：每个字母 = **TTS 读字母名 → 停一拍 → 逐行
  /// 「读音录音 → 停一拍 → 例词录音」**，字母与字母之间再停一拍（`_groupGap`）。
  ///
  /// 传 `allLetterPlayGroups` 就是整张字母表；传 `[letterPlayGroupOf('A')]`
  /// 就是弹层里「连播这 N 种读音」（只有一组，自然不额外停）。
  /// [onGroup] 在每个字母开读前回调（UI 用来高亮那个字母格），
  /// [onRow] 在每条读音开播前回调（弹层里高亮当前行）。
  ///
  /// 字母名走 TTS、没有播完回调，靠这一拍把「字母名」与「第一个读音」错开；
  /// 字母名比一拍还长时（W 这种多音节字母名）两段会轻微叠上——可接受。
  Future<void> playLetterSequence(
    List<LetterPlayGroup> groups, {
    void Function(LetterPlayGroup group)? onGroup,
    void Function(LetterSoundRow row)? onRow,
  }) async {
    final token = ++_sequenceToken;
    for (final (index, group) in groups.indexed) {
      if (token != _sequenceToken) return;
      if (index > 0) {
        await Future<void>.delayed(_groupGap);
        if (token != _sequenceToken) return;
      }
      onGroup?.call(group);
      // 回调里可能刚按了「停止」——那就连字母名都不读
      if (token != _sequenceToken) return;
      await speak(group.letterName);
      await Future<void>.delayed(_phonemeWordGap);
      for (final row in group.rows) {
        if (token != _sequenceToken) return;
        onRow?.call(row);
        await _playLetterRow(row, () => token != _sequenceToken);
      }
    }
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

  /// 停止连播：掐掉当前声音（录音 + 字母名的 TTS），本轮循环随即退出。
  /// 单格点播不受影响。
  Future<void> stopSequence() async {
    _sequenceToken++;
    await _phonemeAudio.stop();
    await _stopSpeaking();
  }

  /// 掐掉正在读的 TTS（引擎未就绪 / 初始化失败时静默跳过）。
  Future<void> _stopSpeaking() async {
    try {
      final engine = await _ttsEngineFuture;
      engine.stop();
    } catch (_) {
      // 引擎初始化失败：没什么可掐的
    }
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
