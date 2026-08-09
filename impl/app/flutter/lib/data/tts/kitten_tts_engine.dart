import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kittentts/kittentts_flutter.dart' as kit;
import 'package:path_provider/path_provider.dart';

import '../../domain/tts/tts_engine.dart';
import 'kitten_tts_session.dart';
import 'tts_cache_manager.dart';

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
  int _utteranceCounter = 0;

  @override
  bool isAvailable() => _session != null;

  @override
  String? unavailabilityReason() => _failureReason;

  @override
  String? speak(String text, {double speed = 1.0}) {
    debugPrint('[KittenTTS.engine] speak: _session=$_session textLen=${text.length}');
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speak: session is null, returning null');
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    debugPrint('[KittenTTS.engine] speak: dispatching id=$id to session');
    session.speak(text, speed: speed, utteranceId: id);
    return id;
  }

  /// 朗读单段：优先缓存命中直接播文件，未命中生成 + 写缓存。
  ///
  /// 返回 utteranceId；失败返回 null。
  Future<String?> speakParagraph({
    required int paragraphId,
    required String text,
    required double speed,
  }) async {
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speakParagraph: session null');
      return null;
    }
    final cm = cache;
    String? cachedPath;
    if (cm != null && paragraphId > 0) {
      cachedPath = await cm.lookupParagraph(paragraphId, speed);
    }
    if (cachedPath != null) {
      debugPrint('[KittenTTS.engine] speakParagraph: cache HIT $cachedPath');
      final id = 'ktk-${_utteranceCounter++}';
      session.playFile(cachedPath, utteranceId: id);
      return id;
    }
    // 未命中：会话内生成 + 写缓存（复用 speakParagraphs 单段语义）
    return speakParagraphs(
      texts: [text],
      paragraphIds: [paragraphId],
      speed: speed,
    );
  }

  /// 按段落全文朗读（首次路径）：逐段生成 → 写缓存 → 播放。
  ///
  /// 返回 utteranceId；失败返回 null。每段完成上报进度 (done/total)。
  Future<String?> speakParagraphs({
    required List<String> texts,
    required List<int> paragraphIds,
    required double speed,
  }) async {
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speakParagraphs: session null');
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    debugPrint('[KittenTTS.engine] speakParagraphs: ${texts.length} paras id=$id');
    session.speakParagraphs(
      texts,
      paragraphIds: paragraphIds,
      speed: speed,
      utteranceId: id,
    );
    return id;
  }

  /// 全文朗读：标题 + 正文段落，单 utterance 内无缝衔接播放。
  ///
  /// 双 worker 流水线（生成 worker 推入队列 / 播放 worker 顺序消费，见
  /// [KittenTtsSession.speakFullArticle]）。进度只计正文段落；全部播完
  /// 触发 finish 回调。返回 utteranceId；失败返回 null。
  Future<String?> speakFullArticle({
    String? title,
    required List<({int id, String text})> paragraphs,
    required double speed,
  }) async {
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] speakFullArticle: session null');
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    debugPrint('[KittenTTS.engine] speakFullArticle: title="${title ?? ""}" paras=${paragraphs.length} id=$id');
    session.speakFullArticle(
      title: title,
      paragraphs: paragraphs,
      speed: speed,
      utteranceId: id,
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

  /// 从缓存播放段落列表（全文朗读缓存路径）。
  ///
  /// 返回 utteranceId 表示全部缓存命中且开始播放，null 表示缓存缺失需 fallback。
  Future<String?> playCachedParagraphs(List<int> paragraphIds, double speed) async {
    debugPrint('[KittenTTS.engine] playCachedParagraphs: ids=$paragraphIds speed=$speed');
    final session = _session;
    if (session == null) {
      debugPrint('[KittenTTS.engine] playCachedParagraphs: session null');
      return null;
    }
    final cm = cache;
    if (cm == null) {
      debugPrint('[KittenTTS.engine] playCachedParagraphs: cache null');
      return null;
    }

    // 按段落顺序查缓存，返回命中的 filePath 列表
    final hits = await cm.lookupArticleParagraphs(paragraphIds, speed);
    debugPrint('[KittenTTS.engine] playCachedParagraphs: hits=${hits.length}/${paragraphIds.length}');
    if (hits.length != paragraphIds.length) return null; // 有未缓存的段落

    final id = 'ktk-${_utteranceCounter++}';
    final paths = paragraphIds.map((pid) => hits[pid]!).toList();
    // 不 await — 顺序播放异步进行，立即返回 id 给 UI 更新状态
    session.playFiles(paths, utteranceId: id);
    return id;
  }

  /// 后台并发预生成所有段落音频并写入缓存。
  ///
  /// 委托给 session（持有引擎与缓存）；引擎空闲时调用（播放结束后），
  /// 不抢占播放；被 stop/新播放打断。
  Future<void> pregenerateParagraphs({
    required List<({int paragraphId, String text})> paragraphs,
    required double speed,
  }) async {
    final session = _session;
    if (session == null) return;
    await session.pregenerateParagraphs(
      paragraphs: paragraphs,
      speed: speed,
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

  @override
  void setOnParagraphStarted(
      void Function(String? utteranceId, int paragraphIndex, int total)?
          callback) {
    // 占位：段落回调透传待 KittenTtsSession 支持段落开始监听后实现
    // （对照 Kotlin 播放 worker 逐段上报，见后续任务）
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
/// marker 文件（.installed）存在则跳过（AssetsInstaller 语义）。返回模型
/// 所在目录。测试注入 [basePathOverride]（文件已放好，跳过拷贝）。
Future<Directory> installModelAssets(
  String assetBasePath, {
  Directory? basePathOverride,
}) async {
  final root = basePathOverride ??
      Directory('${(await getApplicationSupportDirectory()).path}/kittentts');
  final target = Directory('${root.path}/models');
  await target.create(recursive: true);
  if (basePathOverride != null) return target;
  final marker = File('${target.path}/.installed');
  if (await marker.exists()) return target;

  for (final name in const ['kitten_tts_micro_v0_8.onnx', 'voices.npz']) {
    final data = await rootBundle.load('$assetBasePath/$name');
    final file = File('${target.path}/$name');
    await file.writeAsBytes(data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    ));
  }
  await marker.writeAsString('1');
  return target;
}
