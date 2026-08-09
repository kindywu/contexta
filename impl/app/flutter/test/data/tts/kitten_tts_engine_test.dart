import 'dart:io';

import 'package:contexta/data/tts/kitten_tts_engine.dart';
import 'package:contexta/data/tts/kitten_tts_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// KittenTtsEngine 测试：用 fake session 验证 speak/stop/完成回调/初始化失败。
///
/// 对照 Kotlin KittenTtsEngine 设计（temp_docs/kittentts-tts-engine-design.md）：
/// - 惰性初始化（首次 speak 前触发），失败记录具体原因
/// - speak 同步返回 "ktk-N"，生成+播放异步，完成回调带 id
/// - 不可用 → speak 返回 null 且不初始化 session

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('init 成功后 isAvailable 为 true，speak 返回 ktk-N id', () async {
    final engine = _engine();
    await engine.init();

    expect(engine.isAvailable(), isTrue);
    expect(engine.unavailabilityReason(), isNull);

    final id = engine.speak('hello');
    expect(id, 'ktk-0');
    expect(engine.speak('world'), 'ktk-1');
  });

  test('未 init 时 speak 返回 null 且不创建 session', () {
    final factory = _SessionFactory();
    final engine = _engine(factory: factory.create);

    expect(engine.speak('hello'), isNull);
    expect(factory.created, isEmpty);
  });

  test('init 失败记录具体原因，speak 返回 null', () async {
    final engine = _engine(factory: _createThrowing);
    await engine.init();

    expect(engine.isAvailable(), isFalse);
    expect(engine.unavailabilityReason(), contains('初始化失败'));
    expect(engine.speak('hello'), isNull);
  });

  test('setOnSpeakingFinished 透传给 session', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    final finished = <String?>[];
    engine.setOnSpeakingFinished(finished.add);
    session.simulateFinished('ktk-0');
    expect(finished, ['ktk-0']);
  });

  test('speak 转发 text/speed/id 到 session', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    engine.speak('hello', speed: 0.75);

    expect(session.spokenTexts, ['hello']);
    expect(session.spokenSpeeds, [0.75]);
    expect(session.spokenIds, ['ktk-0']);
  });

  test('stop 转发到 session', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    engine.stop();
    expect(session.stopCount, 1);
  });

  test('init 幂等：重复调用不重复创建 session', () async {
    final factory = _SessionFactory();
    final engine = _engine(factory: factory.create);
    await engine.init();
    await engine.init();

    expect(factory.created, hasLength(1));
  });
}

/// 构造引擎：modelBaseOverride 指向临时目录，跳过 rootBundle 加载。
KittenTtsEngine _engine({KittenTtsFactory? factory}) {
  return KittenTtsEngine(
    assetBasePath: '/fake/assets',
    factory: factory ?? _okFactory,
    modelBaseOverride: Directory.systemTemp,
  );
}

class _FakeSession implements KittenTtsSession {
  final List<String> spokenTexts = [];
  final List<double> spokenSpeeds = [];
  final List<String> spokenIds = [];
  int stopCount = 0;
  void Function(String utteranceId)? _finishListener;

  @override
  Future<void> speak(
    String text, {
    required double speed,
    required String utteranceId,
  }) async {
    spokenTexts.add(text);
    spokenSpeeds.add(speed);
    spokenIds.add(utteranceId);
  }

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
  Future<void> stop() async {
    stopCount++;
  }

  @override
  void setFinishListener(void Function(String utteranceId)? listener) {
    _finishListener = listener;
  }

  void simulateFinished(String id) {
    _finishListener?.call(id);
  }

  @override
  void setProgressListener(
      void Function(String utteranceId, int done, int total)? listener) {}

  void Function(String utteranceId, int paragraphIndex, int total)?
      _paragraphStartedListener;

  @override
  void setOnParagraphStarted(
      void Function(String utteranceId, int paragraphIndex, int total)?
          listener) {
    _paragraphStartedListener = listener;
  }

  /// 测试触发：模拟第 [index] 段开始播放（3 段总正文）。
  void simulateParagraphStarted(int index) {
    _paragraphStartedListener?.call('ktk-0', index, 3);
  }

  @override
  Future<void> pregenerateParagraphs({
    required List<({int paragraphId, String text})> paragraphs,
    required double speed,
  }) async {}

  @override
  Future<void> dispose() async {}
}

/// 通用成功工厂：每次返回全新 fake session。
Future<KittenTtsSession> _okFactory({
  required String onnxPath,
  required String voicesPath,
}) async {
  return _FakeSession();
}

/// 指定 fake session 的工厂（验证引擎与 session 的交互）。
KittenTtsFactory _withSession(_FakeSession session) {
  return ({required String onnxPath, required String voicesPath}) async =>
      session;
}

Future<KittenTtsSession> _createThrowing({
  required String onnxPath,
  required String voicesPath,
}) async {
  throw StateError('model file not found');
}

class _SessionFactory {
  final List<String> created = [];
  Future<KittenTtsSession> create({
    required String onnxPath,
    required String voicesPath,
  }) async {
    created.add(onnxPath);
    return _FakeSession();
  }
}
