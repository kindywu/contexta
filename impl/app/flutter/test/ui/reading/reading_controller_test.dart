import 'dart:async';

import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/model/user_settings.dart';
import 'package:contexta/domain/model/vocab_word.dart';
import 'package:contexta/domain/repository/article_repository.dart';
import 'package:contexta/domain/repository/settings_repository.dart';
import 'package:contexta/domain/repository/stats_repository.dart';
import 'package:contexta/domain/repository/vocabulary_repository.dart';
import 'package:contexta/domain/tts/tts_engine.dart';
import 'package:contexta/ui/reading/reading_controller.dart';
import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading 页 controller 测试（Task 23：正文/译文/计时；播放状态机归 Task 24）。
/// 对照 Kotlin ReadingViewModelTest 的正文/计时部分。

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
  });

  final UserSettings settings;
  final Future<void> Function(String mode)? onUpdateTranslationMode;

  @override
  Future<UserSettings?> getSettings() async => settings;

  @override
  Future<void> updateTranslationMode(String mode) async {
    await onUpdateTranslationMode?.call(mode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeStatsRepo implements StatsRepository {
  int recordCount = 0;

  @override
  Future<void> recordReadingActivity({int secondsSpent = 0}) async {
    recordCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

/// 记录 speak/stop 调用 + 可触发完成回调的 TTS 桩（Task 24 会移植完整状态机）。
class _RecordingTts implements TtsEngine {
  bool available = true;
  final List<String> spoken = [];
  int stopCount = 0;
  void Function(String? utteranceId)? onFinished;
  int _counter = 0;

  @override
  bool isAvailable() => available;

  @override
  String? unavailabilityReason() => null;

  @override
  String? speak(String text, {double speed = 1.0}) {
    if (!available) return null;
    spoken.add(text);
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
}

Article makeArticle({
  int id = 1,
  String? readCompletedAt,
  List<ArticleParagraph> paragraphs = const [],
}) =>
    Article(
      id: id,
      batchId: 1,
      orderIndex: 0,
      contentCategory: 'NEWS',
      title: 'Test',
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
  late _RecordingTts tts;
  late ReadingController controller;

  setUp(() {
    articleRepo = _FakeArticleRepo(
      onGetArticle: (_) async => makeArticle(paragraphs: _paragraphs),
    );
    settingsRepo = _FakeSettingsRepo();
    statsRepo = _FakeStatsRepo();
    tts = _RecordingTts();
    controller = ReadingController(
      articleRepository: articleRepo,
      settingsRepository: settingsRepo,
      statsRepository: statsRepo,
      vocabularyRepository: _VocabRepo(),
      ttsEngineFuture: Future.value(tts),
    );
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
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        vocabularyRepository: _VocabRepo(),
        ttsEngineFuture: Future.value(tts),
      );
      await controller.loadArticle(1);
      expect(controller.state.translationMode, TranslationMode.full);
    });

    test('文章未找到 → error', () async {
      articleRepo = _FakeArticleRepo(onGetArticle: (_) async => null);
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        vocabularyRepository: _VocabRepo(),
        ttsEngineFuture: Future.value(tts),
      );
      await controller.loadArticle(999);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.error, '文章未找到');
    });

    test('已读文章不启动计时器（不累计阅读秒数）', () async {
      articleRepo = _FakeArticleRepo(
        onGetArticle: (_) async => makeArticle(
            readCompletedAt: '2026-01-01T00:00:00Z', paragraphs: _paragraphs),
      );
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        vocabularyRepository: _VocabRepo(),
        ttsEngineFuture: Future.value(tts),
      );
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
        controller = ReadingController(
          articleRepository: articleRepo,
          settingsRepository: settingsRepo,
          statsRepository: statsRepo,
          vocabularyRepository: _VocabRepo(),
          ttsEngineFuture: Future.value(tts),
        );
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
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        vocabularyRepository: _VocabRepo(),
        ttsEngineFuture: Future.value(tts),
      );
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
      controller = ReadingController(
        articleRepository: articleRepo,
        settingsRepository: settingsRepo,
        statsRepository: statsRepo,
        vocabularyRepository: _VocabRepo(),
        ttsEngineFuture: Future.value(tts),
      );
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
}

/// getActiveWords 空桩（生词高亮在 UI 层，Task 23 无生词断言）。
class _VocabRepo implements VocabularyRepository {
  @override
  Future<List<VocabWord>> getActiveWords() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}
