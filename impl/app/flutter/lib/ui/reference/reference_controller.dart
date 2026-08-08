import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/tts/tts_engine.dart';

/// Reference 页控制器（对照 Kotlin ReferenceViewModel）：
/// 仅持 TTS 引擎，提供发音入口。
class ReferenceController {
  ReferenceController({required this._ttsEngineFuture});

  final Future<TtsEngine> _ttsEngineFuture;

  /// 朗读文本（引擎未就绪时静默跳过，与页面其它 TTS 消费方一致）。
  Future<void> speak(String text) async {
    try {
      final engine = await _ttsEngineFuture;
      engine.speak(text);
    } catch (_) {
      // 引擎初始化失败：不打断页面交互
    }
  }
}

/// Reference 页控制器 Provider（TTS 引擎单例，跨页面共享）。
final referenceControllerProvider = Provider<ReferenceController>((ref) {
  return ReferenceController(
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
  );
});
