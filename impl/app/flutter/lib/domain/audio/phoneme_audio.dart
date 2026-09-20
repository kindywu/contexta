/// 音标录音（48 个国际音标的真人发音）。
///
/// 背景：TTS 读不出 IPA 符号——早先只能给每个音标配一段「拟音英文拼写」糊弄
/// （`/ɪ/` 读 "it"）。现在改用随包分发的真人录音（`assets/phonetics/`），
/// 音标发音不再经过 TTS；例词仍是 TTS 读。
///
/// 录音与符号的对应表来自 `assets/phonetics/manifest.json`（由
/// `impl/server/tool/fetch-phonetics-yyb.ts` 生成），本文件只做纯逻辑，
/// 读 asset / 播放由 data 层实现（`AssetPhonemeAudio`）。
library;

import 'dart:convert';

/// 播放一个音标的录音。
abstract class PhonemeAudio {
  /// 播放 [phone]（形如 `/iː/`）的录音，**播放结束后**返回；
  /// 返回 `false` 表示录音库里没有这个符号（调用方自行兜底），
  /// 播放失败也返回 `false`（调用方照常走兜底，不静默卡住）。
  Future<bool> play(String phone);
}

/// 归一化音标符号，用于查表（两侧都要过一遍这个函数）：
/// - 去掉包裹的斜杠：`/iː/` → `iː`
/// - `ɡ`(U+0261) → `g`(U+0067)：App 的 `phonicsGroups` 用前者，源站录音清单用后者，
///   是同一个音素（与抓取脚本 `normSymbol` 的规则一致）
/// - 去掉空白
String normalizePhone(String phone) =>
    phone.trim().replaceAll('/', '').replaceAll('\u0261', 'g').trim();

/// 从 manifest.json 解析「符号 → 文件名」映射，键为归一化符号（`iː`）。
///
/// 只认带 file 的条目；JSON 结构异常时返回空表（调用方回退例词 TTS，
/// 不让整个参考页挂掉）。
Map<String, String> phonemeFilesFromManifest(String manifestJson) {
  final out = <String, String>{};
  try {
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map) return out;
    final list = decoded['phonemes'];
    if (list is! List) return out;
    for (final entry in list) {
      if (entry is! Map) continue;
      final symbol = entry['normalized'] ?? entry['symbol'];
      final file = entry['file'];
      if (symbol is String && file is String && symbol.isNotEmpty) {
        out[normalizePhone(symbol)] = file;
      }
    }
  } catch (_) {
    return out;
  }
  return out;
}
