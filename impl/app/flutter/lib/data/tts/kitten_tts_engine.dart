import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
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

  /// 底层 KittenTTS 引擎（init 后 set，pregenerateParagraphs 需直接访问）。
  kit.KittenTTS? _rawEngine;

  KittenTtsSession? _session;
  String? _failureReason;
  void Function(String? utteranceId)? _onSpeakingFinished;
  void Function(String? utteranceId, int done, int total)? _onProgress;
  int _utteranceCounter = 0;
  bool _pregenCancelled = false;

  @override
  bool isAvailable() => _session != null;

  @override
  String? unavailabilityReason() => _failureReason;

  @override
  String? speak(String text, {double speed = 1.0}) {
    debugPrint('[KittenTTS.engine] speak: _session=$_session _rawEngine=$_rawEngine textLen=${text.length}');
    _cancelPregen();
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
    _cancelPregen();
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
    _cancelPregen();
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

  /// 播放本地 WAV 文件（缓存命中时）。
  Future<bool> playFile(String filePath) async {
    _cancelPregen();
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
    _cancelPregen();
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
  /// [Future.wait] 并发发起所有段落的生成（方法通道串行排队，Dart 层
  /// phonemize/tokenize 重叠），比顺序生成快。跳过已缓存的段落。
  /// 用户点击播放时 [_pregenCancelled] 中断剩余写入。
  Future<void> pregenerateParagraphs({
    required List<({int paragraphId, String text})> paragraphs,
    required double speed,
  }) async {
    final cm = cache;
    if (cm == null) return;
    final engine = _rawEngine;
    if (engine == null) return;

    _pregenCancelled = false;

    // 先筛出需要生成的段落（避免无谓并发）
    final toGenerate = <({int paragraphId, String text})>[];
    for (final p in paragraphs) {
      if (_pregenCancelled) break;
      final needs = await cm.needsGenerate(p.paragraphId, speed);
      if (needs) toGenerate.add(p);
    }
    debugPrint('[KittenTTS] pregen: ${toGenerate.length}/${paragraphs.length} need generation');

    // 并发生成（限流：一次最多 3 段并发，避免内存峰值）
    for (var i = 0; i < toGenerate.length; i += 3) {
      if (_pregenCancelled) {
        debugPrint('[KittenTTS] pregen: cancelled');
        break;
      }
      final batch = toGenerate.sublist(
        i,
        i + 3 > toGenerate.length ? toGenerate.length : i + 3,
      );
      await Future.wait(batch.map((p) async {
        if (_pregenCancelled) return;
        try {
          debugPrint('[KittenTTS] pregen: paragraph ${p.paragraphId} (batch ${i ~/ 3 + 1})');
          final result = await engine.generate(p.text, speed: speed);
          if (_pregenCancelled) return;
          final wav = result.wavData();
          await cm.writeParagraph(
            paragraphId: p.paragraphId,
            speed: speed,
            wavData: wav,
          );
          debugPrint('[KittenTTS] pregen: paragraph ${p.paragraphId} OK (${wav.length}B)');
        } catch (e) {
          debugPrint('[KittenTTS] pregen: paragraph ${p.paragraphId} FAILED: $e');
        }
      }));
    }
  }

  @override
  void stop() {
    _cancelPregen();
    _session?.stop();
  }

  void _cancelPregen() {
    _pregenCancelled = true;
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    _onSpeakingFinished = callback;
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

      final engine = await kit.KittenTTS.create(
        config: kit.KittenTTSConfig(
          model: kit.model.micro,
          defaultVoice: kit.voice.bella,
          modelFiles: kit.KittenTTSModelFiles(
            onnxPath: '${dir.path}/kitten_tts_micro_v0_8.onnx',
            voicesPath: '${dir.path}/voices.npz',
          ),
          phonemizer: kit.CEPhonemizer(allowRuleBasedFallback: true),
          analytics: false,
        ),
      );
      _rawEngine = engine;

      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);

      final session = KittenTtsPluginSession(
        engine: engine,
        player: player,
        cache: cache,
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
