import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/model/tts_voice.dart';
import '../../domain/tts/tts_engine.dart';

/// Reference 页控制器（对照 Kotlin ReferenceViewModel）：
/// 仅持 TTS 引擎，提供发音入口。
class ReferenceController {
  ReferenceController({
    required this._ttsEngineFuture,
    required this._voice,
  });

  final Future<TtsEngine> _ttsEngineFuture;
  final TtsVoice Function() _voice;

  /// 朗读文本（引擎未就绪时静默跳过，与页面其它 TTS 消费方一致）。
  Future<void> speak(String text) async {
    try {
      final engine = await _ttsEngineFuture;
      engine.speak(text, voice: _voice());
    } catch (_) {
      // 引擎初始化失败：不打断页面交互
    }
  }
}

/// Reference 页控制器 Provider（TTS 引擎单例，跨页面共享）。
/// voice 用 ref.read（每次 speak 取当前音色）：若在闭包内 ref.watch，
/// 依赖变化后 provider 重建前的窗口期会触发 Riverpod 断言（
/// 'Cannot use ref functions after the dependency of a provider changed'），
/// speak 的 catch 会静默吞掉异常——语音被丢弃。
final referenceControllerProvider = Provider<ReferenceController>((ref) {
  return ReferenceController(
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
    voice: () =>
        ref.read(currentTtsVoiceProvider).valueOrNull ?? TtsVoice.bella,
  );
});
