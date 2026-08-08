import 'dart:io';

import '../../domain/tts/tts_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'kitten_tts_engine.dart';
import 'kitten_tts_session.dart';
import 'system_tts_engine.dart';
import 'tts_cache_manager.dart';

/// flutter_tts 实例工厂（测试注入 fake）。
typedef FlutterTtsFactory = dynamic Function();

/// TTS 引擎组装：KittenTTS 优先，初始化失败自动回退系统 TTS。
///
/// 迁移设计（specs TTS 方案）：`speak(text, speed) → KittenTTS 已初始化 ?
/// KittenTTS.speak() : SystemTts.speak()`；启动时尝试 KittenTTS.create()。
class TtsEngineFactory {
  TtsEngineFactory({
    required this.kittenAssetBasePath,
    this._kittenFactory,
    this._systemFactory,
    this._modelBaseOverride,
    this.cache,
  });

  /// KittenTTS 模型 assets 目录（assets/kittentts_models 的绝对路径）。
  final String kittenAssetBasePath;

  final KittenTtsFactory? _kittenFactory;
  final FlutterTtsFactory? _systemFactory;
  final Directory? _modelBaseOverride;
  final TtsCacheManager? cache;

  /// 创建 TTS 引擎：先尝试 KittenTTS，失败自动回退系统 TTS。
  Future<TtsEngine> create() async {
    debugPrint('[TtsFactory] creating TTS engine...');
    final kitten = _createKittenEngine();
    await kitten.init();
    debugPrint('[TtsFactory] KittenTTS init done, available=${kitten.isAvailable()} reason=${kitten.unavailabilityReason()}');
    if (kitten.isAvailable()) return kitten;

    final system = _createSystemEngine();
    await system.init();
    return system;
  }

  KittenTtsEngine _createKittenEngine() {
    return KittenTtsEngine(
      assetBasePath: kittenAssetBasePath,
      factory: _kittenFactory ?? KittenTtsPluginSession.create,
      modelBaseOverride: _modelBaseOverride,
      cache: cache,
    );
  }

  SystemTtsEngine _createSystemEngine() {
    return SystemTtsEngine(tts: _systemFactory?.call() as FlutterTts?);
  }
}
