/// 音标录音（48 个国际音标 + 各自的例词，均为真人发音）。
///
/// 背景：TTS 读不出 IPA 符号——早先只能给每个音标配一段「拟音英文拼写」糊弄
/// （`/ɪ/` 读 "it"）。现在音标与例词都用随包分发的真人录音
/// （`assets/phonetics/`）：音标发音不经过 TTS，例词优先放录音、缺了才回退 TTS。
///
/// 录音与符号的对应表来自 `assets/phonetics/manifest.json`（由
/// `impl/server/tool/import-phonetics-audio.ts` 从录音包生成），本文件只做纯逻辑，
/// 读 asset / 播放由 data 层实现（`AssetPhonemeAudio`）。
library;

import 'dart:convert';

/// 播放一个音标的录音。
abstract class PhonemeAudio {
  /// 播放 [phone]（形如 `/iː/`）**音标本身**的录音，**播放结束后**返回；
  /// 返回 `false` 表示录音库里没有这个符号（调用方自行兜底），
  /// 播放失败也返回 `false`（调用方照常走兜底，不静默卡住）。
  Future<bool> play(String phone);

  /// 播放 [phone] 对应**例词**的录音（同样是播放结束后返回），
  /// `false` = 没有这个音标的例词录音（调用方回退 TTS 读例词）。
  Future<bool> playWord(String phone);

  /// 立刻掐掉当前播放（连播被「停止」时用）。没在播就什么也不做。
  Future<void> stop();
}

/// 一个音标的两段录音：音标本身 + 例词。
class PhonemeClip {
  const PhonemeClip({required this.file, this.wordFile});

  /// 音标本身的录音（必有）。
  final String file;

  /// 例词的录音；清单里没给就是 null（该音标的例词回退 TTS）。
  final String? wordFile;
}

/// 归一化音标符号，用于查表（两侧都要过一遍这个函数）：
/// - 去掉包裹的斜杠：`/iː/` → `iː`
/// - `ɡ`(U+0261) → `g`(U+0067)：App 的 `phonicsGroups` 用前者，源站录音清单用后者，
///   是同一个音素（与抓取脚本 `normSymbol` 的规则一致）
/// - 去掉空白
String normalizePhone(String phone) =>
    phone.trim().replaceAll('/', '').replaceAll('\u0261', 'g').trim();

/// 从 manifest.json 解析「符号 → 录音」映射，键为归一化符号（`iː`）。
///
/// 只认带 file 的条目（wordFile 可缺）；JSON 结构异常时返回空表（调用方回退例词 TTS，
/// 不让整个参考页挂掉）。
Map<String, PhonemeClip> phonemeClipsFromManifest(String manifestJson) {
  final out = <String, PhonemeClip>{};
  try {
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map) return out;
    final list = decoded['phonemes'];
    if (list is! List) return out;
    for (final entry in list) {
      if (entry is! Map) continue;
      final symbol = entry['normalized'] ?? entry['symbol'];
      final file = entry['file'];
      final wordFile = entry['wordFile'];
      if (symbol is String && file is String && symbol.isNotEmpty) {
        out[normalizePhone(symbol)] = PhonemeClip(
          file: file,
          wordFile: wordFile is String && wordFile.isNotEmpty ? wordFile : null,
        );
      }
    }
  } catch (_) {
    return out;
  }
  return out;
}
