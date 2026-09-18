import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/model/tts_voice.dart';
import '../../domain/tts/tts_engine.dart';
import 'kitten_tts_session.dart';
import 'tts_cache_manager.dart';

/// 送 KittenTTS 合成前的文本规范化：**统一转小写**。
///
/// 插件音素器对**首字母大写**的词会走单独的 capital 词典分支（插件源码
/// `src/cephonemizer/phonemizer.cpp` 的 `$capital` / `capital_dict_`），
/// 未命中时退化为逐字母拼读——2026-09-18 iOS 模拟器实测：标题
/// "Why the Sky Is Blue" 被读成 "S K Y"（正文里小写的 sky 正常）。
/// Kokoro/KittenTTS 模型本身以小写文本训练、音素查表前也会 normalise
/// 大小写，故统一转小写规避。
///
/// 只作用于**送合成**的文本：界面显示、句子高亮、缓存键（段落 + 句序 +
/// 语速 + 音色，不含文本）都不受影响。系统 TTS 走自己的实现，不做此转换
/// （平台 TTS 对大小写处理正确，且转换会改变 NASA 一类缩写的读法）。
String normalizeTtsText(String text) => text.toLowerCase();

/// 句子单元批量规范化（标题另经 [normalizeTtsText]）。
List<SentenceUnit> _normalizeUnits(List<SentenceUnit> units) => [
      for (final u in units)
        (
          paragraphId: u.paragraphId,
          sentenceIndex: u.sentenceIndex,
          text: normalizeTtsText(u.text),
        ),
    ];

/// Flutter 侧 KittenTTS 插件包装（对照 Kotlin 侧 KittenTtsEngine 设计：
/// 本地神经网络合成，作为默认 TTS）。
///
/// 模型（micro，39MB）打包在 Flutter assets 中。首次初始化时解压到应用
/// 支持目录（AssetsInstaller 语义：marker 文件跳过重复拷贝）。
class KittenTtsEngine implements TtsEngine {
  KittenTtsEngine({
    required this.assetBasePath,
    required this.factory,
    this._modelBaseOverride,
    this.cache,
  });

  final String assetBasePath;
  final KittenTtsFactory factory;
  final Directory? _modelBaseOverride;
  final TtsCacheManager? cache;

  KittenTtsSession? _session;
  String? _failureReason;
  void Function(String? utteranceId)? _onSpeakingFinished;
  void Function(String? utteranceId, int done, int total)? _onProgress;
  void Function(String utteranceId, int paragraphIndex, int sentenceIndex,
      int total)? _onSentenceStarted;
  int _utteranceCounter = 0;

  @override
  bool isAvailable() => _session != null;

  @override
  String? unavailabilityReason() => _failureReason;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    debugPrint('[KittenTTS.engine] speak: _session=$_session textLen=${text.length}');
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speak: session is null, returning null');
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    debugPrint('[KittenTTS.engine] speak: dispatching id=$id to session');
    session.speak(normalizeTtsText(text),
        speed: speed, utteranceId: id, voice: voice?.sdkVoiceId);
    return id;
  }

  /// 按句子朗读（单段播放：该段所有句子依次生成 → 写缓存 → 播放）。
  ///
  /// 返回 utteranceId；失败返回 null。每句发声前上报句子位置，每句完成
  /// 上报生成进度 (done/total)。
  Future<String?> speakSentences({
    required List<SentenceUnit> sentences,
    required double speed,
    TtsVoice? voice,
  }) async {
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speakSentences: session null');
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    debugPrint('[KittenTTS.engine] speakSentences: ${sentences.length} sentences id=$id');
    session.speakSentences(
      _normalizeUnits(sentences),
      speed: speed,
      utteranceId: id,
      voice: voice?.sdkVoiceId,
    );
    return id;
  }

  /// 全文朗读：标题 + 正文句子，单 utterance 内无缝衔接播放。
  ///
  /// 双 worker 流水线（生成 worker 推入队列 / 播放 worker 顺序消费，见
  /// [KittenTtsSession.speakFullArticle]）。进度只计正文句子；全部播完
  /// 触发 finish 回调。返回 utteranceId；失败返回 null。
  Future<String?> speakFullArticle({
    String? title,
    required List<SentenceUnit> sentences,
    required double speed,
    TtsVoice? voice,
  }) async {
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speakFullArticle: session null');
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    debugPrint('[KittenTTS.engine] speakFullArticle: title="${title ?? ""}" sentences=${sentences.length} id=$id');
    session.speakFullArticle(
      title: title == null ? null : normalizeTtsText(title),
      sentences: _normalizeUnits(sentences),
      speed: speed,
      utteranceId: id,
      voice: voice?.sdkVoiceId,
    );
    return id;
  }

  /// 播放本地 WAV 文件（缓存命中时）。
  Future<bool> playFile(String filePath) async {
    final session = _session;
    if (session == null) return false;
    final id = 'ktk-${_utteranceCounter++}';
    return session.playFile(filePath, utteranceId: id);
  }

  /// 后台并发预生成所有句子音频并写入缓存。
  ///
  /// 委托给 session（持有引擎与缓存）；引擎空闲时调用（播放结束后），
  /// 不抢占播放；被 stop/新播放打断。
  Future<void> pregenerateSentences({
    required List<SentenceUnit> sentences,
    required double speed,
    TtsVoice? voice,
  }) async {
    final session = _session;
    if (session == null) return;
    await session.pregenerateSentences(
      sentences: _normalizeUnits(sentences),
      speed: speed,
      voice: voice?.sdkVoiceId,
    );
  }

  @override
  void stop() {
    _session?.stop();
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    _onSpeakingFinished = callback;
  }

  /// 注册「句子开始播放」回调（逐句播放方在每句实际发声前调用）。
  /// 带 utterance id、段落索引（正文从 0 起，标题为 [kTitleParagraphIndex]）、
  /// 段内句序号与正文总句数；传 null 注销。透传给 session 层回调
  /// （session 契约 id 非空，收缩安全）。
  @override
  void setOnSentenceStarted(
      void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          callback) {
    _onSentenceStarted = callback;
    debugPrint('[KittenTTS.engine] setOnSentenceStarted: callback=${callback != null}');
  }

  /// 注册生成进度回调（全文朗读流式合成时，句子生成进度）。
  void setOnProgress(void Function(String? utteranceId, int done, int total)? callback) {
    _onProgress = callback;
  }

  Future<void> init() async {
    debugPrint('[KittenTtsEngine] init starting...');
    if (_session != null) return;

    try {
      final dir = await installModelAssets(
        assetBasePath,
        basePathOverride: _modelBaseOverride,
      );

      // 经注入的 factory 创建会话（生产 = KittenTtsPluginSession.create，
      // 测试注入 fake session；不直接调插件，保证测试可运行）
      final session = await factory(
        onnxPath: '${dir.path}/kitten_tts_micro_v0_8.onnx',
        voicesPath: '${dir.path}/voices.npz',
      );
      session.setFinishListener((id) => _onSpeakingFinished?.call(id));
      session.setProgressListener((id, done, total) =>
          _onProgress?.call(id, done, total));
      // 句子播放回调透传：日志兜底，未注册回调时也能从日志定位事件是否触发
      session.setOnSentenceStarted((id, paragraphIndex, sentenceIndex, total) {
        debugPrint('[KittenTTS.engine] sentenceStarted: id=$id '
            'para=$paragraphIndex sentence=$sentenceIndex total=$total');
        _onSentenceStarted?.call(id, paragraphIndex, sentenceIndex, total);
      });
      _session = session;
      debugPrint('[KittenTtsEngine] init SUCCESS');
    } catch (e) {
      _failureReason = 'KittenTTS 初始化失败：${e.toString()}';
      debugPrint('[KittenTtsEngine] init ERROR: $_failureReason');
    }
  }
}

/// 从 Flutter assets 解压 KittenTTS 模型到应用支持目录。
///
/// marker 文件（.installed）存在 **且所有期望文件齐全** 才跳过
/// （AssetsInstaller 语义）。marker 存在但文件缺失时必须重新解压——
/// 词典（en_rules / en_list）打包进 assets 之前安装的旧 marker 会让新
/// 代码跳过拷贝，CEPhonemizer 因此静默降级为纯规则音素器（音质变差）。
/// 返回模型所在目录。测试注入 [basePathOverride]（根目录）与
/// [bundleOverride]（内存资产包，绕过 rootBundle）。
///
/// 除模型外同时解压 CEPhonemizer 词典（en_rules / en_list，共 ~260KB）：
/// 词典缺失时插件会从 raw.githubusercontent.com 下载且 http 无超时——
/// 国内网络下表现为 KittenTTS init 挂起（CPU 0%）。打包进 assets 后
/// create() 以 rulesPath/listPath 直用本地文件，零网络依赖。
Future<Directory> installModelAssets(
  String assetBasePath, {
  Directory? basePathOverride,
  AssetBundle? bundleOverride,
}) async {
  final root = basePathOverride ??
      Directory('${(await getApplicationSupportDirectory()).path}/kittentts');
  final target = Directory('${root.path}/models');
  await target.create(recursive: true);

  const expectedFiles = [
    'kitten_tts_micro_v0_8.onnx',
    'voices.npz',
    'en_rules',
    'en_list',
  ];
  final marker = File('${target.path}/.installed');
  if (await marker.exists() &&
      expectedFiles.every((name) => File('${target.path}/$name').existsSync())) {
    return target;
  }

  final bundle = bundleOverride ?? rootBundle;
  for (final name in expectedFiles) {
    final data = await bundle.load('$assetBasePath/$name');
    final file = File('${target.path}/$name');
    await file.writeAsBytes(data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    ));
  }
  await marker.writeAsString('1');
  return target;
}
