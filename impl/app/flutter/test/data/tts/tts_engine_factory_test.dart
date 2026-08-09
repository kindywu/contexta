import 'dart:io';

import 'package:contexta/data/tts/kitten_tts_engine.dart';
import 'package:contexta/data/tts/kitten_tts_session.dart';
import 'package:contexta/data/tts/system_tts_engine.dart';
import 'package:contexta/data/tts/tts_engine_factory.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_test/flutter_test.dart';

/// TtsEngineFactory 回退逻辑测试：
/// KittenTTS 初始化成功 → 返回 Kitten 引擎；
/// KittenTTS 失败 → 自动回退 SystemTts（引擎链逐个尝试）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsEngineFactory 回退', () {
    test('KittenTTS 可用时返回 Kitten 引擎', () async {
      final factory = TtsEngineFactory(
        kittenAssetBasePath: '/fake/assets',
        kittenFactory: _okKitten,
        systemFactory: _FakeFlutterTts.new,
        modelBaseOverride: Directory.systemTemp,
      );

      final engine = await factory.create();

      expect(engine.isAvailable(), isTrue);
      expect(engine, isA<KittenTtsEngine>());
    });

    test('KittenTTS 初始化失败时回退系统 TTS', () async {
      final factory = TtsEngineFactory(
        kittenAssetBasePath: '/fake/assets',
        kittenFactory: _failKitten,
        systemFactory: _FakeFlutterTts.new,
      );

      final engine = await factory.create();

      expect(engine, isA<SystemTtsEngine>());
    });

    test('KittenTTS 与系统 TTS 都失败时返回不可用系统引擎', () async {
      final factory = TtsEngineFactory(
        kittenAssetBasePath: '/fake/assets',
        kittenFactory: _failKitten,
        systemFactory: _FailFlutterTts.new,
      );

      final engine = await factory.create();

      expect(engine.isAvailable(), isFalse);
      expect(engine.unavailabilityReason(), isNotNull);
    });
  });
}

Future<KittenTtsSession> _okKitten({
  required String onnxPath,
  required String voicesPath,
}) async {
  return _OkSession();
}

Future<KittenTtsSession> _failKitten({
  required String onnxPath,
  required String voicesPath,
}) async {
  throw StateError('model not found');
}
class _OkSession implements KittenTtsSession {
  @override
  Future<void> speak(
    String text, {
    required double speed,
    required String utteranceId,
  }) async {}

  @override
  Future<void> speakFullArticle({
    String? title,
    required List<({int id, String text})> paragraphs,
    required double speed,
    required String utteranceId,
  }) async {}

  @override
  Future<void> speakParagraphs(
    List<String> texts, {
    required List<int> paragraphIds,
    required double speed,
    required String utteranceId,
  }) async {}

  @override
  Future<bool> playFile(String filePath, {required String utteranceId}) async => true;

  @override
  Future<void> playFiles(List<String> filePaths, {required String utteranceId}) async {}

  @override
  Future<void> stop() async {}

  @override
  void setFinishListener(void Function(String utteranceId)? listener) {}

  @override
  void setProgressListener(
      void Function(String utteranceId, int done, int total)? listener) {}

  @override
  void setOnParagraphStarted(
      void Function(String utteranceId, int paragraphIndex, int total)?
          listener) {}

  @override
  Future<void> pregenerateParagraphs({
    required List<({int paragraphId, String text})> paragraphs,
    required double speed,
  }) async {}

  @override
  Future<void> dispose() async {}
}

/// 模拟引擎链：mibrain 未安装、google 安装、默认可用 → 成功。
class _FakeFlutterTts extends FlutterTts {
  _FakeFlutterTts();

  final List<String> engineCalls = [];

  @override
  Future<dynamic> get getEngines async => [
        'com.google.android.tts',
        'com.samsung.SMT',
      ];

  @override
  Future<dynamic> isLanguageAvailable(String language) async => true;

  @override
  Future<dynamic> setEngine(String engine) async {
    engineCalls.add(engine);
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> stop() async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => 1;
}

class _FailFlutterTts extends FlutterTts {
  _FailFlutterTts();

  @override
  Future<dynamic> get getEngines async => const [];

  @override
  Future<dynamic> isLanguageAvailable(String language) async => false;

  @override
  Future<dynamic> setEngine(String engine) async => 0;

  @override
  Future<dynamic> setLanguage(String language) async => 0;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 0;

  @override
  Future<dynamic> stop() async => 0;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async => 0;
}
