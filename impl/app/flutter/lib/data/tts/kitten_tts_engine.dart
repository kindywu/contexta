import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/tts/tts_engine.dart';
import 'kitten_tts_session.dart';

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
  });

  /// assets/kittentts_models 的 flutter asset 键前缀。
  final String assetBasePath;

  /// KittenTTS.create 工厂，测试注入 fake。
  final KittenTtsFactory factory;

  /// 测试注入：模型解压基目录（跳过 rootBundle 加载）。
  final Directory? _modelBaseOverride;

  KittenTtsSession? _session;
  String? _failureReason;
  void Function(String? utteranceId)? _onSpeakingFinished;
  int _utteranceCounter = 0;

  @override
  bool isAvailable() => _session != null;

  @override
  String? unavailabilityReason() => _failureReason;

  @override
  String? speak(String text, {double speed = 1.0}) {
    final session = _session;
    if (session == null) {
      _failureReason ??= 'KittenTTS 尚未初始化';
      return null;
    }
    final id = 'ktk-${_utteranceCounter++}';
    session.speak(text, speed: speed, utteranceId: id);
    return id;
  }

  @override
  void stop() {
    _session?.stop();
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    _onSpeakingFinished = callback;
  }

  /// 初始化（首次调用 speak 前的惰性初始化）。
  ///
  /// 从 assets 解压模型到应用支持目录（marker 跳过重复拷贝），
  /// 构造 KittenTTS（内置 phonemizer 数据，不联网下载）；失败记录具体原因。
  Future<void> init() async {
    if (_session != null) return;
    try {
      final dir = await installModelAssets(
        assetBasePath,
        basePathOverride: _modelBaseOverride,
      );
      final session = await factory(
        onnxPath: '${dir.path}/kitten_tts_micro_v0_8.onnx',
        voicesPath: '${dir.path}/voices.npz',
      );
      session.setFinishListener((id) => _onSpeakingFinished?.call(id));
      _session = session;
    } catch (e) {
      _failureReason = 'KittenTTS 初始化失败：${e.toString()}';
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
  if (basePathOverride != null) return target; // 测试注入：模型文件已就位
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
