import 'dart:async';

import 'package:contexta/domain/llm_client.dart';
import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/model/word_detail.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/repository/word_repository.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reading/reading_controller.dart';
import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading 页 controller 测试（Task 23：正文/译文/计时；Task 24：播放
/// 状态机 + 查词弹窗 + 生词本）。对照 Kotlin ReadingViewModelTest。
///
/// TTS 契约（tts_engine.dart）：controller 传 UI 显示语速（1x / 0.75x），
/// 引擎内部经 TtsSpeedMapper 映射为实际速率（显示语速直接透传）——测试断言
/// speak 收到显示语速。

class _FakeArticleRepo implements ArticleRepository {
  _FakeArticleRepo({
    this.onGetArticle,
    this.onAddReadSeconds,
    this.onTryMarkReadCompleted,
    this.onForceMarkReadCompleted,
  });

  final Future<Article?> Function(int articleId)? onGetArticle;
  final Future<void> Function(int articleId, int delta)? onAddReadSeconds;
  final Future<void> Function(int articleId)? onTryMarkReadCompleted;
  final Future<void> Function(int articleId)? onForceMarkReadCompleted;

  @override
  Future<Article?> getArticle(int articleId) =>
      onGetArticle?.call(articleId) ?? Future.value(null);

  @override
  Future<void> addReadSeconds(int articleId, int deltaSeconds) async {
    await onAddReadSeconds?.call(articleId, deltaSeconds);
  }

  @override
  Future<void> tryMarkReadCompleted(int articleId) async {
    await onTryMarkReadCompleted?.call(articleId);
  }

  @override
  Future<void> forceMarkReadCompleted(int articleId) async {
    await onForceMarkReadCompleted?.call(articleId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeSettingsRepo implements SettingsRepository {
  _FakeSettingsRepo({
    this.settings = const UserSettings(
        isOnboarded: true, translationDisplayMode: 'BLURRED'),
    this.onUpdateTranslationMode,
    this.onUpdateTtsSpeed,
  });

  final UserSettings settings;
  final Future<void> Function(String mode)? onUpdateTranslationMode;
  final Future<void> Function(double speed)? onUpdateTtsSpeed;

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Future<void> updateTtsSpeed(double speed) async {
    await onUpdateTtsSpeed?.call(speed);
  }

  @override
  Future<void> updateTranslationMode(String mode) async {
    await onUpdateTranslationMode?.call(mode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStatsRepo implements StatsRepository {
  int recordCount = 0;
  int wordAddedCount = 0;

  @override
  Future<void> recordReadingActivity({int secondsSpent = 0}) async {
    recordCount++;
  }

  @override
  Future<void> recordWordAdded() async {
    wordAddedCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// 记录 speak/stop 调用 + 可触发完成回调的 TTS 桩（Task 24 移植完整状态机）。
class _RecordingTts implements TtsEngine {
  bool available = true;
  final List<String> spoken = [];
  final List<double> speeds = [];
  int stopCount = 0;
  void Function(String? utteranceId)? onFinished;
  void Function(String? utteranceId, int paragraphIndex, int total)?
      onParagraphStarted;
  int _counter = 0;

  @override
  bool isAvailable() => available;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0}) {
    if (!available) return null;
    spoken.add(text);
    speeds.add(speed);
    _lastId = 'ctx-${_counter++}';
    return _lastId;
  }

  @override
  void stop() {
    stopCount++;
    final id = _lastId;
    _lastId = null;
    onFinished?.call(id);
  }

  String? _lastId;
  void finishUtterance(String? utteranceId) {
    onFinished?.call(utteranceId);
  }

  @override
  void setOnSpeakingFinished(void Function(String? utteranceId)? callback) {
    onFinished = callback;
  }

  @override
  void setOnParagraphStarted(
      void Function(String? utteranceId, int paragraphIndex, int total)?
          callback) {
    onParagraphStarted = callback;
  }

  void simulateParagraphStarted(int index) {
    onParagraphStarted?.call(_lastId, index, 2);
  }
}

/// 可配置查词结果的词库仓储桩（Task 24）。
class _FakeWordRepo implements WordRepository {
  _FakeWordRepo({
    this.onLookupWord,
    this.onSaveLlmResult,
    this.onInvalidateCache,
  });

  final Future<WordDetail?> Function(
      String spelling, Future<WordDetail?> Function(String) llmFallback)?
      onLookupWord;
  final Future<WordDetail> Function(
      String spelling, String? phonetic, List<WordSense> senses)?
      onSaveLlmResult;
  final Future<void> Function(String spelling)? onInvalidateCache;

  @override
  Future<WordDetail?> lookupWord(
          String spelling, Future<WordDetail?> Function(String) llmFallback) =>
      onLookupWord?.call(spelling, llmFallback) ?? Future.value(null);

  @override
  Future<WordDetail> saveLlmResult(
    String spellingDisplay,
    String? phoneticIpa,
    List<WordSense> senses, {
    String? normalized,
  }) =>
      onSaveLlmResult?.call(spellingDisplay, phoneticIpa, senses) ??
      Future.value(_detail(spellingDisplay, phoneticIpa, senses));

  @override
  Future<void> invalidateCache(String spelling) async {
    await onInvalidateCache?.call(spelling);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);

  static WordDetail _detail(
          String spelling, String? phonetic, List<WordSense> senses) =>
      WordDetail(
        wordId: 7,
        spellingDisplay: spelling,
        phoneticIpa: phonetic,
        primarySense: senses.isEmpty ? null : senses.first,
        allSenses: senses,
        isInVocabulary: false,
        vocabularyEntryId: null,
      );
}

/// 可配置 LLM 响应的客户端桩（Task 24）。
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient({this.onCall});

  final Future<LlmResult> Function(String system, String user)? onCall;

  @override
  Future<LlmResult> call(
    String systemPrompt,
    String userPrompt, {
    int? timeoutMs,
  }) async =>
      onCall?.call(systemPrompt, userPrompt) ??
      LlmResult(content: '<spelling>nope</spelling>', retryCount: 0);
}

/// 词库详情夹具。
WordDetail detailOf({
  int wordId = 10,
  String spelling = 'hello',
  String? phonetic = '/həˈləʊ/',
  List<WordSense> senses = const [],
  bool isInVocabulary = false,
  int? vocabularyEntryId,
}) =>
    WordDetail(
      wordId: wordId,
      spellingDisplay: spelling,
      phoneticIpa: phonetic,
      primarySense: senses.isEmpty ? null : senses.first,
      allSenses: senses,
      isInVocabulary: isInVocabulary,
      vocabularyEntryId: vocabularyEntryId,
    );

/// 义项夹具。
WordSense senseOf({
  int id = 0,
  int orderIndex = 0,
  String partOfSpeech = 'interj.',
  String chineseMeaning = '你好',
  String englishDefinition = 'Used as a greeting.',
}) =>
    WordSense(
      id: id,
      orderIndex: orderIndex,
      partOfSpeech: partOfSpeech,
      chineseMeaning: chineseMeaning,
      englishDefinition: englishDefinition,
      examples: const [],
    );

Article makeArticle({
  int id = 1,
  String title = 'Test',
  String? readCompletedAt,
  List<ArticleParagraph> paragraphs = const [],
}) =>
    Article(
      id: id,
      batchId: 1,
      orderIndex: 0,
      contentCategory: 'NEWS',
      title: title,
      status: ArticleStatus.success,
      generationStartedAt: null,
      generationCompletedAt: '2026-08-07T12:00:00+08:00',
      retryCount: 0,
      accumulatedReadSeconds: 0,
      readCompletedAt: readCompletedAt,
      lastRetryAt: null,
      paragraphs: paragraphs,
    );

const _paragraphs = [
  ArticleParagraph(orderIndex: 0, englishText: 'Hello world.', chineseTranslation: '你好世界。'),
  ArticleParagraph(orderIndex: 1, englishText: 'Second paragraph.', chineseTranslation: '第二段。'),
];

void main() {
  late _FakeArticleRepo articleRepo;
  late _FakeSettingsRepo settingsRepo;
  late _FakeStatsRepo statsRepo;
  late _FakeWordRepo wordRepo;
  late _FakeLlmClient llmClient;
  late _VocabRepo vocabRepo;
  late _RecordingTts tts;
  late ReadingController controller;

  ReadingController makeController() => ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        wordRepository: wordRepo,
        llmClient: llmClient,
        vocabularyRepository: vocabRepo,
        ttsEngineFuture: Future.value(tts),
      );

  setUp(() {
    articleRepo = _FakeArticleRepo(
      onGetArticle: (_) async => makeArticle(paragraphs: _paragraphs),
    );
    settingsRepo = _FakeSettingsRepo();
    statsRepo = _FakeStatsRepo();
    wordRepo = _FakeWordRepo();
    llmClient = _FakeLlmClient();
    vocabRepo = _VocabRepo();
    tts = _RecordingTts();
    controller = makeController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('loadArticle', () {
    test('加载文章：标题/段落/已读状态 + 记录阅读活动', () async {
      await controller.loadArticle(1);

      final s = controller.state;
      expect(s.isLoading, isFalse);
      expect(s.title, 'Test');
      expect(s.paragraphs, _paragraphs);
      expect(s.isReadCompleted, isFalse);
      expect(statsRepo.recordCount, 1);
    });

    test('读取设置中的译文模式（BLURRED 持久化 → 显示模式）', () async {
      await controller.loadArticle(1);
      expect(controller.state.translationMode, TranslationMode.blurred);
    });

    test('未知译文模式回退 FULL', () async {
      settingsRepo = _FakeSettingsRepo(
        settings: const UserSettings(
            isOnboarded: true, translationDisplayMode: 'BOGUS'),
      );
      controller = makeController();
      await controller.loadArticle(1);
      expect(controller.state.translationMode, TranslationMode.full);
    });

    test('文章未找到 → error', () async {
      articleRepo = _FakeArticleRepo(onGetArticle: (_) async => null);
      controller = makeController();
      await controller.loadArticle(999);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.error, '文章未找到');
    });

    test('已读文章不启动计时器（不累计阅读秒数）', () async {
      articleRepo = _FakeArticleRepo(
        onGetArticle: (_) async => makeArticle(
            readCompletedAt: '2026-01-01T00:00:00Z', paragraphs: _paragraphs),
      );
      controller = makeController();
      await controller.loadArticle(1);
      expect(controller.state.isReadCompleted, isTrue);

      // 推进 15s：无 tick 回调 → 无 addReadSeconds
      await Future<void>.delayed(const Duration(seconds: 15));
      expect(articleRepo.onAddReadSeconds, isNull); // 未注册即未调用
    });
  });

  group('阅读计时', () {
    test('15s tick 累加阅读秒数 + tryMarkReadCompleted，120s 后自动已读', () {
      fakeAsync((async) {
        var addSecondsCalls = 0;
        var readSeconds = 0;
        articleRepo = _FakeArticleRepo(
          // 模拟 DB 写入：累计 ≥120s 后 getArticle 返回已读 → 自动已读
          onGetArticle: (_) async => makeArticle(
            paragraphs: _paragraphs,
            readCompletedAt: readSeconds >= 120 ? '2026-01-01T00:00:00Z' : null,
          ),
          onAddReadSeconds: (id, delta) async {
            readSeconds += delta;
            addSecondsCalls++;
          },
          onTryMarkReadCompleted: (id) async {},
        );
        controller = makeController();
        // loadArticle 的异步完成依赖 microtask；elapse 前同步推进一帧
        unawaited(controller.loadArticle(1));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 15));
        expect(addSecondsCalls, 1);

        async.elapse(const Duration(seconds: 105)); // 总计 120s → 第 8 个 tick
        expect(addSecondsCalls, 8);
        expect(controller.state.isReadCompleted, isTrue);
      });
    });

    test('手动标记已读 forceMarkReadCompleted + 停止计时', () async {
      var forced = false;
      articleRepo = _FakeArticleRepo(
        onGetArticle: (_) async => makeArticle(paragraphs: _paragraphs),
        onForceMarkReadCompleted: (id) async => forced = true,
      );
      controller = makeController();
      await controller.loadArticle(1);
      await controller.markAsRead();

      expect(forced, isTrue);
      expect(controller.state.isReadCompleted, isTrue);
    });
  });

  group('译文模式', () {
    test('cycleTranslationMode 循环 FULL→DIM→BLURRED→HIDDEN→FULL 并持久化', () async {
      settingsRepo = _FakeSettingsRepo(
        settings: const UserSettings(isOnboarded: true),
        onUpdateTranslationMode: (mode) async {},
      );
      controller = makeController();
      await controller.loadArticle(1);
      expect(controller.state.translationMode, TranslationMode.full);

      controller.cycleTranslationMode();
      expect(controller.state.translationMode, TranslationMode.dim);
      controller.cycleTranslationMode();
      expect(controller.state.translationMode, TranslationMode.blurred);
      controller.cycleTranslationMode();
      expect(controller.state.translationMode, TranslationMode.hidden);
      controller.cycleTranslationMode();
      expect(controller.state.translationMode, TranslationMode.full);
    });

    test('BLURRED 点击揭示译文，10 秒后自动重新模糊', () {
      fakeAsync((async) {
        unawaited(controller.loadArticle(1));
        async.flushMicrotasks();
        controller.cycleTranslationMode();
        controller.cycleTranslationMode(); // → BLURRED

        controller.revealTranslation(0);
        expect(controller.state.revealedParagraphs, {0});

        // 10 秒后自动重新模糊（对照 Kotlin delay(10_000L)）
        async.elapse(const Duration(seconds: 10));
        expect(controller.state.revealedParagraphs, isEmpty);
      });
    });

    test('BLURRED 重复点击揭示不重复计时，切换模式/加载新文章重置揭示', () async {
      await controller.loadArticle(1);
      controller.cycleTranslationMode();
      controller.cycleTranslationMode(); // → BLURRED

      controller.revealTranslation(0);
      controller.revealTranslation(1);
      expect(controller.state.revealedParagraphs, {0, 1});

      // 切换模式清空揭示状态（对照 Kotlin cycleTranslationMode）
      controller.cycleTranslationMode();
      expect(controller.state.revealedParagraphs, isEmpty);

      controller.revealTranslation(0);
      controller.cycleTranslationMode();
      controller.cycleTranslationMode(); // 回到 BLURRED
      await controller.loadArticle(1);
      expect(controller.state.revealedParagraphs, isEmpty);
    });
  });

  group('playParagraph', () {
    test('点击段落播放并设置 speakingParagraphIndex', () async {
      await controller.loadArticle(1);
      controller.playParagraph(0);
      expect(tts.spoken, ['Hello world.']);
      expect(controller.state.speakingParagraphIndex, 0);
    });

    test('再次点击同一段落停止', () async {
      await controller.loadArticle(1);
      controller.playParagraph(0);
      controller.playParagraph(0);
      expect(tts.stopCount, 1);
      expect(controller.state.speakingParagraphIndex, isNull);
    });
  });

  group('播放状态机（Task 24）', () {
    test('段落播放传入显示语速（引擎内部映射实际速率）', () async {
      await controller.loadArticle(1);
      controller.toggleTtsSpeed(); // 0.8x
      controller.playParagraph(0);

      expect(tts.speeds, [0.8]);
      expect(controller.state.speakingParagraphIndex, 0);
    });

    test('自然完成回调清除朗读状态', () async {
      await controller.loadArticle(1);
      controller.playParagraph(0);
      tts.finishUtterance('ctx-0');

      expect(controller.state.isSpeakingFullArticle, isFalse);
      expect(controller.state.speakingParagraphIndex, isNull);
    });

    test('stop 触发完成回调 → 状态清除', () async {
      await controller.loadArticle(1);
      controller.playParagraph(0);
      controller.playParagraph(0); // 同段再点 → stop

      expect(tts.stopCount, 1);
      expect(controller.state.speakingParagraphIndex, isNull);
    });

    test('迟到的旧 utterance 完成回调不清当前新状态（防串扰）', () async {
      await controller.loadArticle(1);
      controller.playParagraph(0); // ctx-0
      controller.playParagraph(1); // ctx-1（打断）

      tts.finishUtterance('ctx-0'); // 迟到的旧回调
      expect(controller.state.speakingParagraphIndex, 1);

      tts.finishUtterance('ctx-1'); // 当前 utterance 完成
      expect(controller.state.speakingParagraphIndex, isNull);
    });

    test('段落播放打断全文朗读', () async {
      await controller.loadArticle(1);
      await controller.startFullArticlePlayback();
      expect(controller.state.isSpeakingFullArticle, isTrue);

      controller.playParagraph(0);
      expect(controller.state.isSpeakingFullArticle, isFalse);
      expect(controller.state.speakingParagraphIndex, 0);
      // 系统 TTS 路径：标题 + 正文拼接为一整段朗读
      expect(tts.spoken, ['Test Hello world. Second paragraph.', 'Hello world.']);
    });

    test('播放全文后段落索引清空', () async {
      await controller.loadArticle(1);
      controller.playParagraph(0);
      await controller.startFullArticlePlayback();

      expect(controller.state.speakingParagraphIndex, isNull);
      expect(controller.state.isSpeakingFullArticle, isTrue);
    });

    test('toggleFullArticlePlayback 朗读中 → 停止', () async {
      await controller.loadArticle(1);
      await controller.startFullArticlePlayback();
      controller.toggleFullArticlePlayback();

      expect(tts.stopCount, 1);
      expect(controller.state.isSpeakingFullArticle, isFalse);
    });

    test('全文内容 = 标题 + 各段落英文拼接', () async {
      await controller.loadArticle(1);
      await controller.startFullArticlePlayback();

      // 系统 TTS 路径：标题 + 正文拼接为一整段朗读
      expect(tts.spoken, ['Test Hello world. Second paragraph.']);
      expect(controller.state.isSpeakingFullArticle, isTrue);
    });

    test('无标题文章 → 跳过标题直接朗读正文', () async {
      articleRepo = _FakeArticleRepo(
        onGetArticle: (_) async => makeArticle(
          title: '',
          paragraphs: _paragraphs,
        ),
      );
      controller = makeController();
      await controller.loadArticle(1);

      await controller.startFullArticlePlayback();

      // 无标题 → 不读标题，直接正文拼接
      expect(tts.spoken, ['Hello world. Second paragraph.']);
      expect(controller.state.isSpeakingFullArticle, isTrue);
    });

    test('TTS 不可用：段落播放 → Snackbar + openTtsSettings', () async {
      tts.available = false;
      await controller.loadArticle(1);
      controller.playParagraph(0);

      expect(controller.state.snackbarMessage, ReadingController.ttsErrorMessage);
      expect(controller.state.openTtsSettings, isTrue);
      expect(controller.state.speakingParagraphIndex, isNull);
    });

    test('TTS 不可用：全文朗读 → Snackbar + openTtsSettings', () async {
      tts.available = false;
      await controller.loadArticle(1);
      controller.toggleFullArticlePlayback();

      expect(controller.state.snackbarMessage, ReadingController.ttsErrorMessage);
      expect(controller.state.openTtsSettings, isTrue);
    });

    test('引擎初始化中：点击播放等待就绪后朗读（不误报不可用）', () async {
      final ready = Completer<TtsEngine>();
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        wordRepository: wordRepo,
        llmClient: llmClient,
        vocabularyRepository: vocabRepo,
        ttsEngineFuture: ready.future,
      );
      await controller.loadArticle(1);

      controller.toggleFullArticlePlayback();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.snackbarMessage, isNull);
      expect(controller.state.openTtsSettings, isFalse);
      // 点击瞬间立即设为播放中（按钮切换），引擎就绪后自动播放
      expect(controller.state.isSpeakingFullArticle, isTrue);

      ready.complete(tts);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSpeakingFullArticle, isTrue);
      expect(tts.spoken, ['Test Hello world. Second paragraph.']);
    });

    test('引擎初始化中：段落播放等待就绪后朗读（不误报不可用）', () async {
      final ready = Completer<TtsEngine>();
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        wordRepository: wordRepo,
        llmClient: llmClient,
        vocabularyRepository: vocabRepo,
        ttsEngineFuture: ready.future,
      );
      await controller.loadArticle(1);

      controller.playParagraph(0);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.snackbarMessage, isNull);
      expect(controller.state.speakingParagraphIndex, isNull);

      ready.complete(tts);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.speakingParagraphIndex, 0);
      expect(tts.spoken, ['Hello world.']);
    });

    test('引擎初始化失败：等待后仍不可用 → 照常提示', () async {
      final ready = Completer<TtsEngine>();
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        wordRepository: wordRepo,
        llmClient: llmClient,
        vocabularyRepository: vocabRepo,
        ttsEngineFuture: ready.future,
      );
      await controller.loadArticle(1);

      controller.toggleFullArticlePlayback();
      ready.complete(tts);
      tts.available = false;
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.snackbarMessage, ReadingController.ttsErrorMessage);
      expect(controller.state.openTtsSettings, isTrue);
      expect(controller.state.isSpeakingFullArticle, isFalse);
    });

    test('TTS 不可用：自动朗读静默跳过（无 Snackbar）', () async {
      tts.available = false;
      settingsRepo = _FakeSettingsRepo(
        settings: const UserSettings(
            isOnboarded: true, autoPlayAudio: true),
      );
      controller = makeController();
      await controller.loadArticle(1);

      expect(tts.spoken, isEmpty);
      expect(controller.state.snackbarMessage, isNull);
      expect(controller.state.isSpeakingFullArticle, isFalse);
    });

    test('clearSnackbar 复位 Snackbar + openTtsSettings', () async {
      tts.available = false;
      await controller.loadArticle(1);
      controller.playParagraph(0);
      controller.clearSnackbar();

      expect(controller.state.snackbarMessage, isNull);
      expect(controller.state.openTtsSettings, isFalse);
    });

    test('语速 1x → 0.8x → 1.2x → 1x 循环切换', () async {
      await controller.loadArticle(1);
      expect(controller.state.ttsSpeed, 1.0);

      controller.toggleTtsSpeed();
      expect(controller.state.ttsSpeed, 0.8);

      controller.toggleTtsSpeed();
      expect(controller.state.ttsSpeed, 1.2);

      controller.toggleTtsSpeed();
      expect(controller.state.ttsSpeed, 1.0);
    });

    test('切换语速回写设置（全局生效）', () async {
      final written = <double>[];
      settingsRepo = _FakeSettingsRepo(
        settings: const UserSettings(isOnboarded: true, ttsSpeed: 0.8),
        onUpdateTtsSpeed: (speed) async => written.add(speed),
      );
      controller = makeController();

      // 进入文章：语速从设置读取（0.8）
      await controller.loadArticle(1);
      expect(controller.state.ttsSpeed, 0.8);

      // 切换：本地状态 + 回写设置
      controller.toggleTtsSpeed();
      expect(controller.state.ttsSpeed, 1.2);
      expect(written, [1.2]);
    });

    test('自动朗读：设置开启进入文章自动播全文（含标题）', () async {
      settingsRepo = _FakeSettingsRepo(
        settings: const UserSettings(
            isOnboarded: true, autoPlayAudio: true),
      );
      controller = makeController();
      await controller.loadArticle(1);

      // 自动朗读同样包含标题（系统 TTS 拼接）
      expect(tts.spoken, ['Test Hello world. Second paragraph.']);
      expect(controller.state.isSpeakingFullArticle, isTrue);
    });
  });

  group('查词弹窗（Task 24）', () {
    test('showWordSheet 立即显示 loading，查词成功后回填', () async {
      wordRepo = _FakeWordRepo(
        onLookupWord: (spelling, _) async => detailOf(
          spelling: 'Hello',
          senses: [senseOf()],
        ),
      );
      controller = makeController();
      await controller.loadArticle(1);

      controller.showWordSheet('hello');
      expect(controller.state.isWordSheetVisible, isTrue);
      expect(controller.state.wordSheetData?.isLoading, isTrue);

      await Future<void>.delayed(Duration.zero); // 等 _lookupWord 完成
      final data = controller.state.wordSheetData!;
      expect(data.isLoading, isFalse);
      expect(data.word, 'Hello');
      expect(data.phonetic, '/həˈləʊ/');
      expect(data.senses, hasLength(1));
      expect(data.senses.first.partOfSpeech, 'interj.');
      expect(data.isInVocabulary, isFalse);
    });

    test('查词失败降级：仅词头，无义项', () async {
      wordRepo = _FakeWordRepo(onLookupWord: (_, _) async => null);
      controller = makeController();
      await controller.loadArticle(1);

      controller.showWordSheet('unknown');
      await Future<void>.delayed(Duration.zero);

      final data = controller.state.wordSheetData!;
      expect(data.isLoading, isFalse);
      expect(data.word, 'unknown');
      expect(data.senses, isEmpty);
      expect(data.phonetic, isNull);
    });

    test('词库未命中时走 LLM fallback 并落库回填', () async {
      var llmCalled = false;
      var saved = false;
      llmClient = _FakeLlmClient(
        onCall: (system, user) async {
          llmCalled = true;
          expect(system, isNotEmpty);
          expect(user, contains('hello'));
          return const LlmResult(
            content: '<spelling>hello</spelling>'
                '<phonetic>/həˈləʊ/</phonetic>'
                '<sense><partOfSpeech>interj.</partOfSpeech>'
                '<chineseMeaning>你好</chineseMeaning>'
                '<englishDefinition>Greeting.</englishDefinition>'
                '</sense>',
            retryCount: 0,
          );
        },
      );
      wordRepo = _FakeWordRepo(
        onLookupWord: (spelling, llmFallback) => llmFallback(spelling),
        onSaveLlmResult: (spelling, phonetic, senses) async {
          saved = true;
          return detailOf(
            wordId: 42,
            spelling: spelling,
            phonetic: phonetic,
            senses: senses,
          );
        },
      );
      controller = makeController();
      await controller.loadArticle(1);

      controller.showWordSheet('hello');
      await Future<void>.delayed(Duration.zero);

      expect(llmCalled, isTrue);
      expect(saved, isTrue);
      final data = controller.state.wordSheetData!;
      expect(data.word, 'hello');
      expect(data.wordId, 42);
    });

    test('同词性义项相邻排列（组序 = 首次出现序）', () async {
      wordRepo = _FakeWordRepo(
        onLookupWord: (spelling, _) async => detailOf(
          senses: [
            senseOf(id: 1, partOfSpeech: 'n.', chineseMeaning: '名词义1'),
            senseOf(id: 2, partOfSpeech: 'v.', chineseMeaning: '动词义1'),
            senseOf(id: 3, partOfSpeech: 'n.', chineseMeaning: '名词义2'),
          ],
        ),
      );
      controller = makeController();
      await controller.loadArticle(1);

      controller.showWordSheet('run');
      await Future<void>.delayed(Duration.zero);

      // Kotlin LinkedHashMap 分组：同词性义项相邻，组序 = 词性首次出现序
      final senses = controller.state.wordSheetData!.senses;
      expect(senses.map((s) => s.partOfSpeech).toList(), ['n.', 'n.', 'v.']);
      expect(senses.map((s) => s.chineseMeaning).toList(),
          ['名词义1', '名词义2', '动词义1']);
    });

    test('hideWordSheet 关闭弹窗并清空数据', () async {
      await controller.loadArticle(1);
      controller.showWordSheet('hello');
      await Future<void>.delayed(Duration.zero);

      controller.hideWordSheet();
      expect(controller.state.isWordSheetVisible, isFalse);
      expect(controller.state.wordSheetData, isNull);
    });
  });

  group('生词本（Task 24）', () {
    test('addToVocabulary 更新弹窗数据 + 正文高亮集合（即时生效）', () async {
      var added = false;
      var cacheInvalidated = <String>[];
      wordRepo = _FakeWordRepo(
        onLookupWord: (spelling, _) async => detailOf(wordId: 10),
        onInvalidateCache: (spelling) async => cacheInvalidated.add(spelling),
      );
      vocabRepo = _VocabRepo(
        onAddWord: (wordId) async {
          added = true;
          expect(wordId, 10);
          return 99;
        },
      );
      controller = makeController();
      await controller.loadArticle(1);
      controller.showWordSheet('hello');
      await Future<void>.delayed(Duration.zero);

      await controller.addToVocabulary();

      expect(added, isTrue);
      expect(statsRepo.wordAddedCount, 1);
      expect(cacheInvalidated, ['hello']);
      final data = controller.state.wordSheetData!;
      expect(data.isInVocabulary, isTrue);
      expect(data.vocabularyEntryId, 99);
      expect(controller.state.vocabularyWords, contains('hello'));
    });

    test('removeFromVocabulary 解除高亮', () async {
      var removed = false;
      var cacheInvalidated = <String>[];
      wordRepo = _FakeWordRepo(
        onLookupWord: (spelling, _) async => detailOf(
          wordId: 10,
          isInVocabulary: true,
          vocabularyEntryId: 99,
        ),
        onInvalidateCache: (spelling) async => cacheInvalidated.add(spelling),
      );
      vocabRepo = _VocabRepo(
        onRemoveWord: (entryId) async {
          removed = true;
          expect(entryId, 99);
        },
      );
      controller = makeController();
      await controller.loadArticle(1);
      controller.showWordSheet('hello');
      await Future<void>.delayed(Duration.zero);

      await controller.removeFromVocabulary();

      expect(removed, isTrue);
      expect(cacheInvalidated, ['hello']);
      final data = controller.state.wordSheetData!;
      expect(data.isInVocabulary, isFalse);
      expect(data.vocabularyEntryId, isNull);
      expect(controller.state.vocabularyWords, isNot(contains('hello')));
    });
  });
}

/// 生词仓储桩（Task 24 扩展：可配置 addWord/removeWord）。
class _VocabRepo implements VocabularyRepository {
  _VocabRepo({
    this.onAddWord,
    this.onRemoveWord,
  });

  final Future<int?> Function(int wordId)? onAddWord;
  final Future<void> Function(int entryId)? onRemoveWord;

  @override
  Future<List<VocabWord>> getActiveWords() async => const [];

  @override
  Future<int?> addWord(int wordId) async =>
      onAddWord?.call(wordId) ?? Future.value(null);

  @override
  Future<void> removeWord(int entryId, {String reason = 'MANUAL_REMOVAL'}) async {
    await onRemoveWord?.call(entryId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}
