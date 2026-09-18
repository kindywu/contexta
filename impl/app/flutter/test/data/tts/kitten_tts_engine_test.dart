import 'dart:io';

import 'package:contexta/data/tts/kitten_tts_engine.dart';
import 'package:contexta/data/tts/kitten_tts_session.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
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

  test('setOnSentenceStarted 透传给 session', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    final started = <(String, int, int, int)>[];
    // 引擎层签名 id 可空（对齐 TtsEngine 接口）；session 契约保证非空，透传时收缩安全
    engine.setOnSentenceStarted(
        (id, paragraphIndex, sentenceIndex, total) =>
            started.add((id!, paragraphIndex, sentenceIndex, total)));
    session.simulateSentenceStarted(1, 2);

    expect(started, [('ktk-0', 1, 2, 3)]);
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

  test('speak/speakSentences/speakFullArticle 透传 voice 到会话', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    engine.speak('hello', voice: TtsVoice.hugo);
    expect(session.lastVoice, 'hugo');

    await engine.speakSentences(
        sentences: [(paragraphId: 1, sentenceIndex: 0, text: 'a')],
        speed: 1.0,
        voice: TtsVoice.leo);
    expect(session.lastVoice, 'leo');

    await engine.speakFullArticle(
        sentences: [(paragraphId: 1, sentenceIndex: 0, text: 'a')],
        speed: 1.0,
        voice: TtsVoice.luna);
    expect(session.lastVoice, 'luna');
  });

  test('送合成前统一转小写（标题首字母大写词不被逐字母拼读）', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    engine.speak('Why the Sky Is Blue');
    expect(session.spokenTexts, ['why the sky is blue']);

    await engine.speakSentences(
        sentences: [
          (paragraphId: 1, sentenceIndex: 0, text: 'The Sky Is Blue.'),
          (paragraphId: 1, sentenceIndex: 1, text: 'Lisa asks Tom.'),
        ],
        speed: 1.0);
    expect(session.lastSentenceTexts, ['the sky is blue.', 'lisa asks tom.']);

    await engine.speakFullArticle(
        title: 'Why the Sky Is Blue',
        sentences: [(paragraphId: 2, sentenceIndex: 0, text: 'Earth\'s sky Is Blue.')],
        speed: 1.0);
    expect(session.lastTitle, 'why the sky is blue');
    expect(session.lastSentenceTexts, ["earth's sky is blue."]);

    await engine.pregenerateSentences(
        sentences: [(paragraphId: 3, sentenceIndex: 0, text: 'NASA And Sky')],
        speed: 1.0);
    expect(session.lastSentenceTexts, ['nasa and sky']);
  });

  test('转小写只动送合成的文本，句子位置（段落 id / 句序）原样保留', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    await engine.speakSentences(
        sentences: [(paragraphId: 727, sentenceIndex: 3, text: 'Hello World')],
        speed: 1.0);

    expect(session.lastUnits, [(727, 3, 'hello world')]);
  });

  test('normalizeTtsText：纯函数语义（小写化，含撇号与数字不变）', () {
    expect(normalizeTtsText('Why the Sky Is Blue'), 'why the sky is blue');
    expect(normalizeTtsText("Earth's Sky"), "earth's sky");
    expect(normalizeTtsText('already lower 123'), 'already lower 123');
  });

  test('voice 为空时透传 null（引擎默认音色）', () async {
    final session = _FakeSession();
    final engine = _engine(factory: _withSession(session));
    await engine.init();

    engine.speak('hello');
    expect(session.lastVoice, isNull);
  });
}

/// 构造引擎：modelBaseOverride 指向临时目录，预置完整安装态
/// （.installed marker + 4 个资产文件），installModelAssets 走跳过分支。
KittenTtsEngine _engine({KittenTtsFactory? factory}) {
  final root = Directory.systemTemp.createTempSync('kittentts_engine_test');
  final models = Directory('${root.path}/models')..createSync();
  File('${models.path}/.installed').writeAsStringSync('1');
  for (final name in [
    'kitten_tts_micro_v0_8.onnx',
    'voices.npz',
    'en_rules',
    'en_list',
  ]) {
    File('${models.path}/$name').writeAsBytesSync([1]);
  }
  addTearDown(() => root.deleteSync(recursive: true));
  return KittenTtsEngine(
    assetBasePath: '/fake/assets',
    factory: factory ?? _okFactory,
    modelBaseOverride: root,
  );
}

class _FakeSession implements KittenTtsSession {
  final List<String> spokenTexts = [];
  final List<double> spokenSpeeds = [];
  final List<String> spokenIds = [];

  /// 最近一次收到的 [voice]（Task 7 断言 voice 透传依赖）。
  String? lastVoice;
  int stopCount = 0;
  void Function(String utteranceId)? _finishListener;

  @override
  Future<void> speak(
    String text, {
    required double speed,
    required String utteranceId,
    String? voice,
  }) async {
    spokenTexts.add(text);
    spokenSpeeds.add(speed);
    spokenIds.add(utteranceId);
    lastVoice = voice;
  }

  /// 最近一次收到的正文句子文本 / 标题（转小写断言依赖）。
  List<String> lastSentenceTexts = [];
  String? lastTitle;

  /// 最近一次收到的句子单元（位置 + 文本，断言「只改文本不改位置」）。
  List<(int, int, String)> lastUnits = [];

  @override
  Future<void> speakFullArticle({
    String? title,
    required List<SentenceUnit> sentences,
    required double speed,
    required String utteranceId,
    String? voice,
  }) async {
    lastVoice = voice;
    lastTitle = title;
    lastSentenceTexts = [for (final s in sentences) s.text];
    lastUnits = [for (final s in sentences) (s.paragraphId, s.sentenceIndex, s.text)];
  }

  @override
  Future<void> speakSentences(
    List<SentenceUnit> sentences, {
    required double speed,
    required String utteranceId,
    String? voice,
  }) async {
    lastVoice = voice;
    lastSentenceTexts = [for (final s in sentences) s.text];
    lastUnits = [for (final s in sentences) (s.paragraphId, s.sentenceIndex, s.text)];
  }

  @override
  Future<bool> playFile(String filePath, {required String utteranceId}) async => true;

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

  void Function(String utteranceId, int paragraphIndex, int sentenceIndex,
      int total)? _sentenceStartedListener;

  @override
  void setOnSentenceStarted(
      void Function(String utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          listener) {
    _sentenceStartedListener = listener;
  }

  /// 测试触发：模拟第 [paragraphIndex] 段第 [sentenceIndex] 句开始播放
  /// （正文共 3 句）。
  void simulateSentenceStarted(int paragraphIndex, int sentenceIndex) {
    _sentenceStartedListener?.call('ktk-0', paragraphIndex, sentenceIndex, 3);
  }

  @override
  Future<void> pregenerateSentences({
    required List<SentenceUnit> sentences,
    required double speed,
    String? voice,
  }) async {
    lastVoice = voice;
    lastSentenceTexts = [for (final s in sentences) s.text];
    lastUnits = [for (final s in sentences) (s.paragraphId, s.sentenceIndex, s.text)];
  }

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
