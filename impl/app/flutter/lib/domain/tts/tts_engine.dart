import '../model/tts_voice.dart';

/// 朗读单元 = 文章里的一句话（生成 / 缓存 / 播放位置上报的调度粒度）。
///
/// [paragraphId] 为所属段落主键（0 = 未持久化的测试数据，不落缓存）；
/// [sentenceIndex] 为段内句子序号（0 起）；[text] 为句子原文。
typedef SentenceUnit = ({int paragraphId, int sentenceIndex, String text});

/// 标题单元的段落索引哨兵：全文朗读时标题也作为一个朗读单元上报
/// （读标题即高亮标题），与正文段落（从 0 起）区分。
/// 标题不参与缓存（无段落 ID），句序号恒为 0。
const int kTitleParagraphIndex = -1;

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
  /// [speed] 为该引擎的实际语速参数（UI 显示语速经 [TtsSpeedMapper] 映射）；
  /// [voice] 为目标音色，null 时用引擎默认音色。系统 TTS 无音色语义，
  /// 实现忽略该参数。
  String? speak(String text, {double speed = 1.0, TtsVoice? voice});

  /// 停止当前 utterance。
  void stop();

  /// 注册当前 utterance 结束回调（自然结束 / stop / 被新 utterance 打断）。
  /// 带结束的 utterance id；传 null 注销。
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback);

  /// 注册「句子开始播放」回调（播放方在每个朗读单元实际发声前调用）。
  /// 带 utterance id、段落索引（正文从 0 起，标题为 [kTitleParagraphIndex]）、
  /// 段内句子序号与全篇句子总数；传 null 注销。
  /// 无句子边界信息的引擎（系统 TTS 拼接朗读）不触发。
  void setOnSentenceStarted(
    void Function(
      String? utteranceId,
      int paragraphIndex,
      int sentenceIndex,
      int total,
    )? callback,
  );
}

/// UI 显示语速 → 引擎实际语速的映射（对照 Kotlin ReadingViewModel.actualSpeechRate）。
///
/// UI 标签 1x/0.75x 直接透传给引擎（1→1、0.75→0.75），不缩放；
/// KittenTTS 语速语义与系统不同，不走此映射。
abstract interface class TtsSpeedMapper {
  double actualRate(double displaySpeed);
}

class SystemTtsSpeedMapper implements TtsSpeedMapper {
  const SystemTtsSpeedMapper();

  @override
  double actualRate(double displaySpeed) => displaySpeed;
}
