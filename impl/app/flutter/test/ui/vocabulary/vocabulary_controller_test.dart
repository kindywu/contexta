import 'package:contexta/domain/model/tts_voice.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/vocabulary/vocabulary_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vocabulary 页 controller 测试（Task 25）。
/// 对照 Kotlin VocabularyViewModelTest：自动朗读 4 用例 + 复习流程
/// （markCorrect 达阈值转 MASTERED / markIncorrect 重置 streak /
/// 全部复习完 → 总结页 / restart）。
///
/// 注：生产代码对生词列表 .shuffled()，顺序随机——涉及具体单词的断言
/// 用单元素列表；「切到下一个」的断言用相对比较（新词 ≠ 旧词）。

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo({
    this.settings = const UserSettings(isOnboarded: true),
  });

  final UserSettings settings;

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeVocabRepo implements VocabularyRepository {
  _FakeVocabRepo({
    this.words = const [],
    this.onMarkCorrect,
    this.onMarkIncorrect,
  });

  /// 活跃列表（可变：测试可直接修改模拟 DB 状态变化）。
  List<VocabWord> words;
  final Future<void> Function(int entryId, int masteryThreshold)? onMarkCorrect;
  final Future<void> Function(int entryId)? onMarkIncorrect;

  @override
  Future<List<VocabWord>> getActiveWords() async => words;

  @override
  Future<void> markCorrect(int entryId, {int masteryThreshold = 1}) async {
    await onMarkCorrect?.call(entryId, masteryThreshold);
  }

  @override
  Future<void> markIncorrect(int entryId) async {
    await onMarkIncorrect?.call(entryId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _TtsStub implements TtsEngine {
  bool available = true;
  final List<String> spoken = [];

  @override
  bool isAvailable() => available;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0, TtsVoice? voice}) {
    if (!available) return null;
    spoken.add(text);
    return 'ctx-$text';
  }

  @override
  void stop() {}

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {}

  @override
  void setOnParagraphStarted(
      void Function(String? utteranceId, int paragraphIndex, int total)?
          callback) {}
}

VocabWord vocabWord({
  int entryId = 1,
  int wordId = 1,
  String spelling = 'hello',
  String? phonetic,
  int streak = 0,
  List<WordSense> senses = const [],
}) =>
    VocabWord(
      entryId: entryId,
      wordId: wordId,
      instanceNumber: 1,
      status: VocabStatus.new_,
      correctReviewStreak: streak,
      spellingDisplay: spelling,
      phoneticIpa: phonetic,
      allSenses: senses,
    );

WordSense sense({
  String partOfSpeech = 'interj.',
  String chineseMeaning = '你好',
  String englishDefinition = 'Used as a greeting.',
  String sentenceEn = 'Hello world.',
  String sentenceZh = '你好世界。',
}) =>
    WordSense(
      id: 1,
      orderIndex: 1,
      partOfSpeech: partOfSpeech,
      chineseMeaning: chineseMeaning,
      englishDefinition: englishDefinition,
      examples: [
        ExampleSentence(
          id: 1,
          orderIndex: 1,
          sentenceEn: sentenceEn,
          sentenceZh: sentenceZh,
          isPrimary: true,
        ),
      ],
    );

void main() {
  late _FakeSettingsRepo settingsRepo;
  late _FakeVocabRepo vocabRepo;
  late _TtsStub tts;
  late VocabularyController controller;

  /// 构造 controller（loadVocabulary 在构造内异步执行，先 await 完成）。
  Future<VocabularyController> createController({
    bool autoPlayAudio = false,
    List<VocabWord> words = const [],
  }) async {
    settingsRepo = _FakeSettingsRepo(
      settings: UserSettings(isOnboarded: true, autoPlayAudio: autoPlayAudio),
    );
    vocabRepo = _FakeVocabRepo(words: words);
    tts = _TtsStub();
    final c = VocabularyController(
      vocabularyRepository: vocabRepo,
      settingsRepository: settingsRepo,
      ttsEngineFuture: Future.value(tts),
    );
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  tearDown(() {
    controller.dispose();
  });

  group('加载与自动朗读（对照 Kotlin 4 用例）', () {
    test('生词为空 → 空态（isLoading=false，无当前词）', () async {
      controller = await createController();
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.totalCount, 0);
      expect(controller.state.currentWord, isNull);
    });

    test('autoPlayAudio 开启：显示首个词并自动朗读', () async {
      controller = await createController(
        autoPlayAudio: true,
        words: [vocabWord(spelling: 'hello')],
      );
      expect(controller.state.currentWord?.word, 'hello');
      expect(tts.spoken, ['hello']);
    });

    test('autoPlayAudio 关闭：不自动朗读', () async {
      controller = await createController(
        autoPlayAudio: false,
        words: [vocabWord(spelling: 'hello')],
      );
      expect(controller.state.currentWord?.word, 'hello');
      expect(tts.spoken, isEmpty);
    });

    test('TTS 不可用：自动朗读静默跳过', () async {
      tts = _TtsStub()..available = false;
      controller = VocabularyController(
        vocabularyRepository: _FakeVocabRepo(
            words: [vocabWord(spelling: 'hello')]),
        settingsRepository: _FakeSettingsRepo(
          settings: const UserSettings(
              isOnboarded: true, autoPlayAudio: true),
        ),
        ttsEngineFuture: Future.value(tts),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.currentWord?.word, 'hello');
      expect(tts.spoken, isEmpty);
    });

    test('goNext 显示下一个词并自动朗读（顺序随机，用相对比较）', () async {
      controller = await createController(
        autoPlayAudio: true,
        words: [
          vocabWord(entryId: 1, spelling: 'alpha'),
          vocabWord(entryId: 2, spelling: 'beta'),
        ],
      );
      final first = controller.state.currentWord?.word;
      expect(first, isNotNull);
      expect(tts.spoken, [first]);

      controller.goNext();
      final second = controller.state.currentWord?.word;
      expect(second, isNotNull);
      expect(second, isNot(first));
      expect(tts.spoken, [first, second]);
    });

    test('卡片包含词性块与例句数据', () async {
      controller = await createController(
        words: [
          vocabWord(
            spelling: 'hello',
            phonetic: '/həˈləʊ/',
            senses: [sense()],
          ),
        ],
      );
      final card = controller.state.currentWord!;
      expect(card.phonetic, '/həˈləʊ/');
      expect(card.senses, hasLength(1));
      expect(card.senses.first.partOfSpeech, 'interj.');
      expect(card.senses.first.examples.single.sentenceEn, 'Hello world.');
      expect(card.reviewStreak, 0);
      expect(card.masteryThreshold, 1);
    });
  });

  group('复习流程', () {
    test('markIncorrect：记录 + 切到下一个', () async {
      var incorrectCalled = false;
      settingsRepo = _FakeSettingsRepo();
      vocabRepo = _FakeVocabRepo(
        words: [
          vocabWord(entryId: 1, spelling: 'alpha'),
          vocabWord(entryId: 2, spelling: 'beta'),
        ],
        onMarkIncorrect: (entryId) async => incorrectCalled = true,
      );
      tts = _TtsStub();
      controller = VocabularyController(
        vocabularyRepository: vocabRepo,
        settingsRepository: settingsRepo,
        ttsEngineFuture: Future.value(tts),
      );
      await Future<void>.delayed(Duration.zero);

      final first = controller.state.currentWord!;
      await controller.markIncorrect();

      expect(incorrectCalled, isTrue);
      expect(controller.state.reviewedCount, 1);
      expect(controller.state.currentWord?.entryId, isNot(first.entryId));
    });

    test('markCorrect 未达阈值：词留在列表，streak 记录', () async {
      // masteryThreshold=3，streak 0 → 一次正确后仍活跃
      settingsRepo = _FakeSettingsRepo(
        settings: const UserSettings(
            isOnboarded: true, masteryThresholdN: 3),
      );
      vocabRepo = _FakeVocabRepo(
        words: [vocabWord(entryId: 1, spelling: 'alpha')],
        onMarkCorrect: (entryId, threshold) async {
          expect(threshold, 3);
        },
      );
      tts = _TtsStub();
      controller = VocabularyController(
        vocabularyRepository: vocabRepo,
        settingsRepository: settingsRepo,
        ttsEngineFuture: Future.value(tts),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.markCorrect();

      // getActiveWords 仍返回原列表 → 未掌握 → 下一词（列表末尾 → 总结页）
      expect(controller.state.reviewedCount, 1);
      expect(controller.state.newlyKnownCount, 0);
      expect(controller.state.isSummary, isTrue);
    });

    test('markCorrect 达阈值：转 MASTERED 移除列表 + newlyKnownCount', () async {
      var correctCalled = false;
      // 模拟 DB：markCorrect 后该词不再活跃（从列表中移除）。
      // 列表是 shuffle 的，当前词可能是任一 entryId → 按传入的 entryId 删除，
      // 保证断言确定性。
      vocabRepo = _FakeVocabRepo(
        words: [
          vocabWord(entryId: 1, spelling: 'alpha'),
          vocabWord(entryId: 2, spelling: 'beta'),
        ],
        onMarkCorrect: (entryId, threshold) async {
          correctCalled = true;
          vocabRepo.words =
              vocabRepo.words.where((w) => w.entryId != entryId).toList();
        },
      );
      settingsRepo = _FakeSettingsRepo();
      tts = _TtsStub();
      controller = VocabularyController(
        vocabularyRepository: vocabRepo,
        settingsRepository: settingsRepo,
        ttsEngineFuture: Future.value(tts),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.markCorrect();

      expect(correctCalled, isTrue);
      expect(controller.state.newlyKnownCount, 1);
      expect(controller.state.reviewedCount, 1);
    });

    test('全部复习完 → 总结页；restart 重新开始', () async {
      controller = await createController(
        words: [vocabWord(entryId: 1, spelling: 'alpha')],
      );
      expect(controller.state.isSummary, isFalse);

      controller.goNext(); // 列表末尾 → 总结
      expect(controller.state.isSummary, isTrue);
      expect(controller.state.currentWord, isNull);

      controller.restart();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSummary, isFalse);
      expect(controller.state.currentWord, isNotNull);
    });

    test('goPrevious 回到上一个词；首个词不再回退', () async {
      controller = await createController(
        words: [
          vocabWord(entryId: 1, spelling: 'alpha'),
          vocabWord(entryId: 2, spelling: 'beta'),
        ],
      );
      final first = controller.state.currentWord!;
      controller.goNext();
      expect(controller.state.currentWord?.entryId, isNot(first.entryId));

      controller.goPrevious();
      expect(controller.state.currentWord?.entryId, first.entryId);

      controller.goPrevious(); // 已到首个 → 不动
      expect(controller.state.currentIndex, 0);
    });
  });
}
