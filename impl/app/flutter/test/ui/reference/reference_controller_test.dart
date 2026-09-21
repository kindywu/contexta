import 'dart:async';

import 'package:contexta/domain/audio/phoneme_audio.dart';
import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reference/reference_controller.dart';
import 'package:contexta/ui/reference/reference_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference 页 controller 测试（对照 Kotlin ReferenceViewModel）：
/// - speak 转发到 TTS 引擎
/// - 引擎初始化失败时静默（不抛出）
/// - 音标格发音走录音（不经过 TTS），录音缺失才兜底读例词

class _RecordingTts implements TtsEngine {
  final List<String> spoken = [];
  final List<TtsVoice?> voices = [];
  int stopCount = 0;

  /// 是否在 speak 时立刻上报「读完」（false = 模拟引擎不上报，只有超时能放行）。
  bool reportFinished = true;
  void Function(String?)? _onFinished;

  /// 引擎注册的「读完」回调（测试里手动触发，模拟迟到的完成事件）。
  void Function(String?)? get speakCallback => _onFinished;

  TtsVoice? get lastVoice => voices.isEmpty ? null : voices.last;

  @override
  bool isAvailable() => true;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    spoken.add(text);
    voices.add(voice);
    if (reportFinished) _onFinished?.call('ctx-1');
    return 'ctx-1';
  }

  @override
  void stop() => stopCount++;

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) =>
      _onFinished = callback;

  @override
  void setOnSentenceStarted(
      void Function(String? utteranceId, int paragraphIndex, int sentenceIndex,
              int total)?
          callback) {}
}

/// 假录音库：记下播过哪些音标 / 例词 / 字母读音行例词；
/// `missing` / `missingWord` / `missingLetterWord` 里的符号按「无该段录音」返回 false。
class _FakePhonemeAudio implements PhonemeAudio {
  _FakePhonemeAudio({
    this.missing = const {},
    this.missingWord = const {},
    this.missingLetterWord = const {},
  });

  final Set<String> missing;
  final Set<String> missingWord;
  final Set<String> missingLetterWord;
  final List<String> played = [];
  final List<String> playedWords = [];
  final List<String> playedLetterWords = [];
  int stopCount = 0;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<bool> play(String phone) async {
    if (missing.contains(phone)) return false;
    played.add(phone);
    return true;
  }

  @override
  Future<bool> playWord(String phone) async {
    if (missingWord.contains(phone)) return false;
    playedWords.add(phone);
    return true;
  }

  @override
  Future<bool> playLetterWord(String phone) async {
    if (missingLetterWord.contains(phone)) return false;
    playedLetterWords.add(phone);
    return true;
  }
}

const _phoneticCell = ReferenceCellData(
  char: '/iː/',
  reading: '单元音',
  example: 'see',
  exampleIpa: '/siː/',
  exampleCn: '',
  isPhonetic: true,
);

const _bookCell = ReferenceCellData(
  char: '/ʊ/',
  reading: '单元音',
  example: 'book',
  exampleIpa: '/bʊk/',
  exampleCn: '',
  isPhonetic: true,
);

const _aboutCell = ReferenceCellData(
  char: '/ə/',
  reading: '单元音',
  example: 'about',
  exampleIpa: '/əˈbaʊt/',
  exampleCn: '',
  isPhonetic: true,
);

const _alphabetCell = ReferenceCellData(
  char: 'A a',
  reading: '/eɪ/',
  example: 'Apple',
  exampleIpa: '/ˈæpəl/',
  exampleCn: '苹果',
  isPhonetic: false,
);

void main() {
  test('speak 转发文本到引擎并携带音色', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      phonemeAudio: _FakePhonemeAudio(),
    );

    await controller.speak('A. Apple');

    expect(tts.spoken, ['A. Apple']);
  });

  test('音色固定 bella：不传就用默认值，且每次朗读都一样', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      phonemeAudio: _FakePhonemeAudio(),
    );

    await controller.speak('A. Apple');
    await controller.speak('B. Banana');

    expect(tts.voices, [TtsVoice.bella, TtsVoice.bella]);
  });

  test('音色可由构造参数指定（默认 bella 之外的取值）', () async {
    final tts = _RecordingTts();
    final controller = ReferenceController(
      ttsEngineFuture: Future.value(tts),
      phonemeAudio: _FakePhonemeAudio(),
      voice: TtsVoice.hugo,
    );

    await controller.speak('A. Apple');

    expect(tts.lastVoice, TtsVoice.hugo);
  });

  test('引擎初始化失败 → 静默跳过不抛出', () async {
    final controller = ReferenceController(
      ttsEngineFuture: Future.error(StateError('engine init failed')),
      phonemeAudio: _FakePhonemeAudio(),
    );

    await controller.speak('hello');

    expect(true, isTrue); // 到达此处即未抛出
  });

  group('音标格发音走录音（不走 TTS）', () {
    test('符号点击：放录音，TTS 不发声', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
      );

      await controller.playSymbol(_phoneticCell);

      expect(audio.played, ['/iː/']);
      expect(tts.spoken, isEmpty, reason: '音标发音不该经过 TTS');
    });

    test('符号点击：录音缺失才兜底读例词（不读 IPA）', () async {
      final tts = _RecordingTts();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: _FakePhonemeAudio(missing: {'/iː/'}),
      );

      await controller.playSymbol(_phoneticCell);

      expect(tts.spoken, ['see']);
    });

    test('发音按钮：音标录音 → 例词录音，两段都走录音（TTS 不发声）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      await controller.playCell(_phoneticCell);

      expect(audio.played, ['/iː/']);
      expect(audio.playedWords, ['/iː/']);
      expect(tts.spoken, isEmpty, reason: '两段都有录音，不该惊动 TTS');
    });

    test('例词录音缺失：那一拍之后回退 TTS 读例词（不带 IPA、不带注脚）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio(missingWord: {'/iː/'});
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      await controller.playCell(_phoneticCell);

      expect(audio.played, ['/iː/']);
      expect(audio.playedWords, isEmpty);
      // 只有例词本身：不带 IPA、不带音标注脚、不拼成句子
      expect(tts.spoken, ['see']);
    });

    test('录音播完到例词之间留一拍（默认 1s）', () async {
      expect(ReferenceController.defaultPhonemeWordGap, const Duration(seconds: 1));

      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: const Duration(milliseconds: 120),
      );

      final sw = Stopwatch()..start();
      await controller.playCell(_phoneticCell);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100),
          reason: '例词应在音标录音后停顿一拍再开口');
      expect(audio.playedWords, ['/iː/']);
    });

    test('音标录音没放成就不白等：立刻读例词（例词录音照放）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio(missing: {'/iː/'});
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        // 默认 1s；若实现无条件等待，这个用例会明显变慢（下面的耗时断言兜底）
        phonemeWordGap: const Duration(seconds: 1),
      );

      final sw = Stopwatch()..start();
      await controller.playCell(_phoneticCell);
      sw.stop();

      expect(audio.played, isEmpty);
      expect(audio.playedWords, ['/iː/'], reason: '音标缺录音不影响例词录音');
      expect(tts.spoken, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(500), reason: '没有录音就不该等那一拍');
    });

    test('两段录音都没有：直接 TTS 读例词', () async {
      final tts = _RecordingTts();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: _FakePhonemeAudio(missing: {'/iː/'}, missingWord: {'/iː/'}),
        phonemeWordGap: const Duration(seconds: 1),
      );

      final sw = Stopwatch()..start();
      await controller.playCell(_phoneticCell);
      sw.stop();

      expect(tts.spoken, ['see']);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });

    test('例词点击：音标格放例词录音，录音缺失才回退 TTS', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
      );

      await controller.playExample(_phoneticCell);
      expect(audio.playedWords, ['/iː/']);
      expect(audio.played, isEmpty, reason: '点例词只读例词，不读音标');
      expect(tts.spoken, isEmpty);

      final fallbackTts = _RecordingTts();
      final fallback = ReferenceController(
        ttsEngineFuture: Future.value(fallbackTts),
        phonemeAudio: _FakePhonemeAudio(missingWord: {'/iː/'}),
      );
      await fallback.playExample(_phoneticCell);
      expect(fallbackTts.spoken, ['see']);
    });

    test('连播：按顺序把每个音标的两段读完，并逐格回调', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      final focused = <String>[];
      await controller.playSequence(
        const [
          [_phoneticCell, _bookCell],
        ],
        onCell: (cell) => focused.add(cell.char),
      );

      expect(focused, ['/iː/', '/ʊ/'], reason: '每格开播前回调，顺序即表格顺序');
      expect(audio.played, ['/iː/', '/ʊ/']);
      expect(audio.playedWords, ['/iː/', '/ʊ/']);
      expect(tts.spoken, isEmpty, reason: '两段都有录音，连播不经过 TTS');
    });

    test('连播：每格之间同样留一拍', () async {
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: _FakePhonemeAudio(),
        phonemeWordGap: const Duration(milliseconds: 100),
      );

      final sw = Stopwatch()..start();
      await controller.playSequence(const [
        [_phoneticCell, _bookCell],
      ]);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(200),
          reason: '两格各停一拍 = 至少 200ms');
    });

    test('连播：组与组之间再停一拍（组间那一拍是 groupGap）', () async {
      expect(ReferenceController.defaultGroupGap, const Duration(seconds: 1));

      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: _FakePhonemeAudio(),
        phonemeWordGap: Duration.zero,
        groupGap: const Duration(milliseconds: 150),
      );

      // 两组：第一组一格、第二组两格——跨一次组界只停 groupGap 那一拍
      // （格子之间那一拍用的是 phonemeWordGap，这里已置零）
      final sw = Stopwatch()..start();
      await controller.playSequence(const [
        [_phoneticCell],
        [_bookCell, _aboutCell],
      ]);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150));
      expect(sw.elapsedMilliseconds, lessThan(300), reason: '只该停一次');
    });

    test('连播：同一组里格子之间也停一拍（例词读完歇一拍再进下一格）', () async {
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: _FakePhonemeAudio(),
        phonemeWordGap: const Duration(milliseconds: 100),
        groupGap: Duration.zero,
      );

      final sw = Stopwatch()..start();
      await controller.playSequence(const [
        [_phoneticCell, _bookCell],
      ]);
      sw.stop();

      // 两格各一拍「音标 → 例词」+ 格子之间一拍 = 3 拍
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(280),
          reason: '少了格子之间那一拍只有 2 拍');
      expect(sw.elapsedMilliseconds, lessThan(600));
    });

    test('连播：只播一组（「播这组」）没有组边界，不等组间那一拍', () async {
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: _FakePhonemeAudio(),
        phonemeWordGap: Duration.zero,
        groupGap: const Duration(seconds: 1),
      );

      final sw = Stopwatch()..start();
      await controller.playSequence(const [
        [_phoneticCell, _bookCell],
      ]);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: '同组不该等组间那 1s');
    });

    test('连播：空表直接结束（不回调、不发声）', () async {
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      await controller.playSequence(const [], onCell: (_) => fail('不该回调'));

      expect(audio.played, isEmpty);
      expect(audio.playedWords, isEmpty);
    });

    test('连播中停止：掐掉声音，且当前格不再往下读', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      final playing = controller.playSequence(
        const [
          [_phoneticCell, _bookCell, _aboutCell],
        ],
        onCell: (cell) {
          // 第一格开播后立刻按「停止」（模拟用户在播放途中点停止）
          if (cell.char == '/iː/') unawaited(controller.stopSequence());
        },
      );
      await playing;

      expect(audio.stopCount, greaterThan(0), reason: '停止要立刻掐声');
      expect(audio.played, ['/iː/'], reason: '停在第一格，不再读后面的音标');
      expect(audio.playedWords, isEmpty, reason: '停下后当前格的例词也不该冒出来');
      expect(tts.spoken, isEmpty);
    });

    test('连播：一次点播不受停止影响（playCell 不是连播）', () async {
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      await controller.playCell(_phoneticCell);

      expect(audio.played, ['/iː/']);
      expect(audio.playedWords, ['/iː/']);
      expect(audio.stopCount, 0);
    });

    test('字母格：符号点击读字母名、例词点击读例词，都不放录音', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
      );

      await controller.playSymbol(_alphabetCell);
      expect(tts.spoken, ['A']);
      expect(audio.played, isEmpty);

      await controller.playExample(_alphabetCell);
      expect(tts.spoken, ['A', 'Apple']);
      expect(audio.playedWords, isEmpty);
    });

    test('字母格「发音」：字母名 → 停一拍 → 例词（两段 TTS，与音标格同节奏）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: const Duration(milliseconds: 120),
      );

      final sw = Stopwatch()..start();
      await controller.playCell(_alphabetCell);
      sw.stop();

      expect(tts.spoken, ['A', 'Apple'], reason: '两段独立朗读，不是一句「A. Apple」');
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100),
          reason: '字母名与例词之间要停一拍');
      expect(audio.played, isEmpty);
      expect(audio.playedWords, isEmpty);
    });
  });

  group('字母读音行（复用音标录音）', () {
    ReferenceController controllerWith(_RecordingTts tts, _FakePhonemeAudio audio) =>
        ReferenceController(
          ttsEngineFuture: Future.value(tts),
          phonemeAudio: audio,
          phonemeWordGap: Duration.zero,
        );

    test('点读音：只放读音本身的录音（TTS 不发声）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();

      await controllerWith(tts, audio).playLetterSound(soundRowsOf('B').single);

      expect(audio.played, ['/b/']);
      expect(audio.playedWords, isEmpty, reason: '点读音不读例词');
      expect(tts.spoken, isEmpty);
    });

    test('点例词：只放例词录音（音标库那套）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();

      await controllerWith(tts, audio).playLetterExample(soundRowsOf('B').single);

      expect(audio.playedWords, ['/b/']);
      expect(audio.played, isEmpty, reason: '点例词不读音标');
      expect(tts.spoken, isEmpty);
    });

    test('组合音行（/ks/ 没有读音录音）：点读音兜底 TTS 读例词（不读 IPA）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final row = soundRowsOf('X').first;
      expect(row.phoneme, '/ks/');

      await controllerWith(tts, audio).playLetterSound(row);

      expect(audio.played, isEmpty);
      expect(tts.spoken, ['box'], reason: '只有例词本身，IPA 不进 TTS');
    });

    test('自带例词的行走 letterWords 那批：X 的 /z/ 例词放的是 xylophone', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final row = soundRowsOf('X').last;
      expect(row.phoneme, '/z/');
      expect(row.hasAudio, isTrue);
      expect(row.isOwnExample, isTrue);

      await controllerWith(tts, audio).playLetterExample(row);

      expect(audio.playedLetterWords, ['/z/'], reason: '走 TTS 预生成的那批（xylophone）');
      expect(audio.playedWords, isEmpty, reason: '不碰音标库的 zoo');
      expect(tts.spoken, isEmpty);
    });

    test('自带例词的录音缺失：回退 TTS 读例词', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio(missingLetterWord: {'/z/'});

      await controllerWith(tts, audio).playLetterExample(soundRowsOf('X').last);

      expect(tts.spoken, ['xylophone']);
    });

    test('音标库那套的例词录音缺失：回退 TTS 读例词', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio(missingWord: {'/b/'});

      await controllerWith(tts, audio).playLetterExample(soundRowsOf('B').single);

      expect(tts.spoken, ['bag']);
    });

    test('单行点播不受「停止」影响（不是连播）', () async {
      final audio = _FakePhonemeAudio();
      final controller = controllerWith(_RecordingTts(), audio);

      await controller.playLetterSound(soundRowsOf('B').single);

      expect(audio.played, ['/b/']);
      expect(audio.stopCount, 0);
    });
  });

  group('字母连播', () {
    test('字母内连播：先 TTS 读字母名，再逐行「读音 → 例词」，逐行回调', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      final rows = <String>[];
      await controller.playLetterSequence(
        [letterPlayGroupOf('B')],
        onRow: (row) => rows.add(row.phoneme),
      );

      expect(tts.spoken, ['B'], reason: '开头读字母名');
      expect(audio.played, ['/b/']);
      expect(audio.playedWords, ['/b/']);
      expect(rows, ['/b/']);
    });

    test('连播：读音没录音的行不白等那一拍（直接读例词）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        // 默认 1s；若实现无条件等待，这个用例会明显变慢（下面的耗时断言兜底）
        phonemeWordGap: const Duration(seconds: 1),
      );
      final cluster = soundRowsOf('X').first; // /ks/：没有读音录音

      final sw = Stopwatch()..start();
      await controller.playLetterSequence([
        LetterPlayGroup('X x', [cluster]),
      ]);
      sw.stop();

      expect(audio.played, isEmpty, reason: '组合音没有读音录音');
      expect(audio.playedLetterWords, ['/ks/'], reason: '跳过读音段，直接读例词');
      expect(tts.spoken, ['X'], reason: '只有字母名走 TTS');
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(900),
          reason: '字母名那一拍照停');
      expect(sw.elapsedMilliseconds, lessThan(1600),
          reason: '读音没录音就不再等第二拍');
    });

    test('字母名等它读完才往下走（不是发出去就数拍子）', () async {
      final tts = _RecordingTts()..reportFinished = false;
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
        speakTimeout: const Duration(milliseconds: 300),
      );

      final playing = controller.playLetterSequence([letterPlayGroupOf('B')]);
      await pumpEventQueue();
      expect(tts.spoken, ['B']);
      expect(audio.played, isEmpty, reason: '字母名还没读完，不往下读');

      // 引擎补报「读完」→ 立刻继续（不必等超时）
      final sw = Stopwatch()..start();
      tts.reportFinished = true;
      tts.speakCallback?.call('ctx-1');
      await playing;
      sw.stop();

      expect(audio.played, ['/b/']);
      expect(sw.elapsedMilliseconds, lessThan(250), reason: '报完成就该放行，不靠超时');
    });

    test('引擎不上报完成：最多等 speakTimeout 就放行（不卡死整轮）', () async {
      final tts = _RecordingTts()..reportFinished = false;
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
        speakTimeout: const Duration(milliseconds: 150),
      );

      final sw = Stopwatch()..start();
      await controller.playLetterSequence([letterPlayGroupOf('B')]);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(140), reason: '等了超时那一段');
      expect(audio.played, ['/b/'], reason: '放行后照常往下读');
    });

    test('例词读完到下一条读音之间停一拍', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: const Duration(milliseconds: 100),
      );
      // 取 A 的前两条读音：/eɪ/ 与 /æ/
      final rows = soundRowsOf('A').take(2).toList();

      final sw = Stopwatch()..start();
      await controller.playLetterSequence([LetterPlayGroup('A a', rows)]);
      sw.stop();

      expect(audio.played, ['/eɪ/', '/æ/']);
      // 字母名后一拍 + 每行「读音→例词」各一拍 + 两行之间一拍 = 4 拍
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(380),
          reason: '两行之间那一拍要算进去（少了它只有 3 拍）');
      expect(sw.elapsedMilliseconds, lessThan(800));
    });

    test('字母名读完之后停一拍再进第一个读音', () async {
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(_RecordingTts()),
        phonemeAudio: _FakePhonemeAudio(),
        phonemeWordGap: const Duration(milliseconds: 150),
      );

      final sw = Stopwatch()..start();
      await controller.playLetterSequence([letterPlayGroupOf('B')]);
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(300),
          reason: '字母名后一拍 + 读音后一拍 = 至少 300ms');
    });

    test('全部连播：字母与字母之间再停一拍，并逐字母回调', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
        groupGap: const Duration(milliseconds: 150),
      );

      final letters = <String>[];
      final sw = Stopwatch()..start();
      await controller.playLetterSequence(
        [letterPlayGroupOf('B'), letterPlayGroupOf('H')],
        onGroup: (group) => letters.add(group.letterName),
      );
      sw.stop();

      expect(letters, ['B', 'H'], reason: '每格开播前回调，顺序即字母表顺序');
      expect(tts.spoken, ['B', 'H']);
      expect(audio.played, ['/b/', '/h/']);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150),
          reason: '跨了一次字母界 = 至少停一拍');
      expect(sw.elapsedMilliseconds, lessThan(400), reason: '只该停一次');
    });

    test('空表直接结束（不回调、不发声）', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      await controller.playLetterSequence(const [], onGroup: (_) => fail('不该回调'));

      expect(tts.spoken, isEmpty);
      expect(audio.played, isEmpty);
    });

    test('中途停止：掐掉录音与字母名 TTS，当前行不补读、后面的行不读', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      // A 的第二个读音开播时按「停止」（模拟用户在播放途中点停止）
      final playing = controller.playLetterSequence(
        [letterPlayGroupOf('A')],
        onRow: (row) {
          if (row.phoneme == '/æ/') unawaited(controller.stopSequence());
        },
      );
      await playing;
      await pumpEventQueue(); // 「停止」是回调里发起的，等它把掐声做完

      expect(audio.stopCount, greaterThan(0), reason: '停止要立刻掐声');
      expect(tts.stopCount, greaterThan(0), reason: '字母名的 TTS 也要掐');
      expect(audio.played, ['/eɪ/'], reason: '停在第二行，第一行已读完');
      expect(audio.playedWords, ['/eɪ/'], reason: '当前行不补读例词');
      expect(tts.spoken, ['A']);
    });

    test('停止发生在读完字母名之前：这一格连字母名都不读', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
      );

      final playing = controller.playLetterSequence(
        [letterPlayGroupOf('B'), letterPlayGroupOf('H')],
        onGroup: (group) {
          if (group.letterName == 'B') unawaited(controller.stopSequence());
        },
      );
      await playing;
      await pumpEventQueue();

      expect(tts.spoken, isEmpty);
      expect(audio.played, isEmpty);
      expect(tts.stopCount, greaterThan(0));
    });

    test('全部 26 个字母的连播分组：63 条读音，按字母顺序', () async {
      final tts = _RecordingTts();
      final audio = _FakePhonemeAudio();
      final controller = ReferenceController(
        ttsEngineFuture: Future.value(tts),
        phonemeAudio: audio,
        phonemeWordGap: Duration.zero,
        groupGap: Duration.zero,
      );

      final letters = <String>[];
      await controller.playLetterSequence(
        allLetterPlayGroups,
        onGroup: (group) => letters.add(group.letterName),
      );

      final rows = allLetterPlayGroups.expand((g) => g.rows).toList();
      final withAudio = rows.where((r) => r.hasAudio).length;
      final libraryWords = rows.where((r) => !r.isOwnExample).length;
      expect(letters.length, 26);
      expect(audio.played.length, withAudio, reason: '有读音录音的都读一遍');
      expect(audio.playedWords.length, libraryWords, reason: '音标库那套例词');
      expect(audio.playedLetterWords.length, rows.length - libraryWords,
          reason: '自带例词的行走 TTS 预生成那批（X 三条）');
      expect(tts.spoken.length, 26, reason: '只有 26 个字母名走 TTS');
      expect(audio.played.first, '/eɪ/');
      expect(audio.played.last, '/z/');
    });
  });
}
