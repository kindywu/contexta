/// TTS 引擎接口（对照 Kotlin domain/tts/TtsEngine.kt）。
///
/// 由 data 层实现。消费方（Reading/Reference/Vocabulary 页面）只依赖此接口，
/// 不感知 KittenTTS / 系统 TTS 的实现差异。
abstract interface class TtsEngine {
  /// 引擎是否可用（初始化成功）。
  bool isAvailable();

  /// 不可用原因的人类可读描述；可用时为 null。
  String? unavailabilityReason();

  /// 朗读文本（打断当前 utterance）。返回 utterance id；失败返回 null。
  ///
  /// [speed] 为该引擎的实际语速参数（UI 显示语速经 [TtsSpeedMapper] 映射）。
  String? speak(String text, {double speed = 1.0});

  /// 停止当前 utterance。
  void stop();

  /// 注册当前 utterance 结束回调（自然结束 / stop / 被新 utterance 打断）。
  /// 带结束的 utterance id；传 null 注销。
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback);
}

/// UI 显示语速 → 引擎实际语速的映射（对照 Kotlin ReadingViewModel.actualSpeechRate）。
///
/// UI 标签只需 1x/0.75x；系统 TTS 用更慢的自然语速：
/// "0.75x" → 0.45f（极慢，利于学习），"1x" → 0.70f（慢于系统默认）。
/// KittenTTS 语速语义与系统不同，不走此映射（设计文档：实现时验证）。
abstract interface class TtsSpeedMapper {
  double actualRate(double displaySpeed);
}

class SystemTtsSpeedMapper implements TtsSpeedMapper {
  const SystemTtsSpeedMapper();

  @override
  double actualRate(double displaySpeed) =>
      displaySpeed < 0.8 ? 0.45 : 0.70;
}
