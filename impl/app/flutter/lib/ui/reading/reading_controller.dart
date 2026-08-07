import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/model/article.dart';
import '../../domain/repository/article_repository.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/repository/stats_repository.dart';
import '../../domain/repository/vocabulary_repository.dart';
import '../../domain/repository/word_repository.dart';
import '../../domain/tts/tts_engine.dart';
import 'translation_visibility.dart';

/// Reading 页 UI 状态（对照 Kotlin ReadingUiState）。
class ReadingUiState {
  const ReadingUiState({
    this.title,
    this.paragraphs = const [],
    this.translationMode = TranslationMode.full,
    this.revealedParagraphs = const {},
    this.vocabularyWords = const {},
    this.isLoading = true,
    this.error,
    this.isReadCompleted = false,
    this.speakingParagraphIndex,
  });

  final String? title;
  final List<ArticleParagraph> paragraphs;
  final TranslationMode translationMode;

  /// BLURRED 模式下被点击揭示译文的段落索引。
  final Set<int> revealedParagraphs;

  /// 生词（已归一化的小写拼写）→ 正文高亮。
  final Set<String> vocabularyWords;
  final bool isLoading;
  final String? error;
  final bool isReadCompleted;

  /// 正在朗读的段落索引（null = 无）。Task 24 扩展全文朗读/查词弹窗状态。
  final int? speakingParagraphIndex;

  ReadingUiState copyWith({
    String? title,
    List<ArticleParagraph>? paragraphs,
    TranslationMode? translationMode,
    Set<int>? revealedParagraphs,
    Set<String>? vocabularyWords,
    bool? isLoading,
    String? error,
    bool? isReadCompleted,
    int? speakingParagraphIndex,
  }) =>
      ReadingUiState(
        title: title ?? this.title,
        paragraphs: paragraphs ?? this.paragraphs,
        translationMode: translationMode ?? this.translationMode,
        revealedParagraphs: revealedParagraphs ?? this.revealedParagraphs,
        vocabularyWords: vocabularyWords ?? this.vocabularyWords,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        isReadCompleted: isReadCompleted ?? this.isReadCompleted,
        speakingParagraphIndex: speakingParagraphIndex,
      );
}

/// Reading 页控制器（对照 Kotlin ReadingViewModel 的正文/译文/计时部分）：
/// - loadArticle：getArticle → 设置（译文模式 + autoPlayAudio）→ 生词集合 →
///   recordReadingActivity → 未读时启动 15s 计时
/// - 计时：15s tick addReadSeconds + tryMarkReadCompleted，达 120s 自动已读；
///   手动标记 forceMarkReadCompleted
/// - cycleTranslationMode：FULL→DIM→BLURRED→HIDDEN→FULL 循环并持久化
/// - revealTranslation：BLURRED 点击揭示，10 秒后自动重新模糊
/// - playParagraph：段落内联播放（点同一段停止；TTS 不可用提示）
class ReadingController extends StateNotifier<ReadingUiState> {
  ReadingController({
    required this._articleRepository,
    required this._settingsRepository,
    required this._vocabularyRepository,
    required this._statsRepository,
    required Future<TtsEngine> ttsEngineFuture,
  }) : super(const ReadingUiState()) {
    // TTS 引擎由 FutureProvider 异步初始化（KittenTTS 模型加载）；就绪后
    // 替换引擎并注册完成回调，期间 playParagraph 静默跳过（同 Kotlin 自动朗读）
    ttsEngineFuture.then(_onTtsReady);
  }

  static const String ttsErrorMessage = '语音引擎未安装，请在系统设置中开启「文字转语音」功能';

  final ArticleRepository _articleRepository;
  final SettingsRepository _settingsRepository;
  final VocabularyRepository _vocabularyRepository;
  final StatsRepository _statsRepository;

  TtsEngine? _ttsEngine;

  int _articleId = -1;
  Timer? _readTimer;
  String? _currentUtteranceId;
  final List<Timer> _revealTimers = [];
  bool _disposed = false;

  void _onTtsReady(TtsEngine engine) {
    if (_disposed) {
      engine.stop();
      return;
    }
    _ttsEngine = engine;
    // 对照 Kotlin init：只有当前 utterance 结束才清状态；迟到的旧 utterance
    // 回调（快速切换播放时）被 id 校验过滤
    engine.setOnSpeakingFinished((utteranceId) {
      if (utteranceId == _currentUtteranceId) {
        _currentUtteranceId = null;
        if (!_disposed) {
          state = state.copyWith(speakingParagraphIndex: null);
        }
      }
    });
  }

  /// 进入页面加载文章（对照 Kotlin loadArticle）。
  Future<void> loadArticle(int articleId) async {
    _articleId = articleId;
    _readTimer?.cancel();

    final article = await _articleRepository.getArticle(articleId);
    final settings = await _settingsRepository.getSettings();

    if (article == null) {
      state = state.copyWith(isLoading: false, error: '文章未找到');
      return;
    }

    final alreadyRead = article.readCompletedAt != null;
    final vocabWords = (await _vocabularyRepository.getActiveWords())
        .map((w) => WordRepository.normalize(w.spellingDisplay))
        .toSet();

    state = state.copyWith(
      title: article.title ?? 'Untitled',
      paragraphs: article.paragraphs,
      translationMode: TranslationMode.fromStorage(
          settings?.translationDisplayMode),
      revealedParagraphs: const {},
      isLoading: false,
      isReadCompleted: alreadyRead,
      vocabularyWords: vocabWords,
      // 切换文章时重置段落播放状态，防止上一篇文章的状态残留
      speakingParagraphIndex: null,
    );

    await _statsRepository.recordReadingActivity();
    if (!alreadyRead) {
      _startReadTimer();
    }
  }

  /// 15 秒一个 tick：累加阅读秒数 + 尝试标记已读；达 120s 后自动已读并停止。
  void _startReadTimer() {
    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_articleId < 0) return;
      await _articleRepository.addReadSeconds(_articleId, 15);
      await _articleRepository.tryMarkReadCompleted(_articleId);
      final article = await _articleRepository.getArticle(_articleId);
      if (article?.readCompletedAt != null) {
        if (!_disposed) {
          state = state.copyWith(isReadCompleted: true);
        }
        _readTimer?.cancel();
      }
    });
  }

  /// 手动标记已读（绕过 120s 阈值）。
  Future<void> markAsRead() async {
    await _articleRepository.forceMarkReadCompleted(_articleId);
    state = state.copyWith(isReadCompleted: true);
    _readTimer?.cancel();
  }

  /// 循环译文模式并持久化（Kotlin 直接存 enum name，DIM 也会持久化）。
  void cycleTranslationMode() {
    final next = state.translationMode.next;
    state = state.copyWith(
      translationMode: next,
      revealedParagraphs: const {},
    );
    _settingsRepository.updateTranslationMode(next.name.toUpperCase());
  }

  /// BLURRED 模式点击揭示译文，10 秒后自动重新模糊。
  void revealTranslation(int paragraphIndex) {
    state = state.copyWith(
      revealedParagraphs: {...state.revealedParagraphs, paragraphIndex},
    );
    final timer = Timer(const Duration(seconds: 10), () {
      if (!_disposed) {
        state = state.copyWith(
          revealedParagraphs: {...state.revealedParagraphs}..remove(paragraphIndex),
        );
      }
    });
    _revealTimers.add(timer);
  }

  /// 朗读段落；再次点击正在朗读的段落停止。
  void playParagraph(int index) {
    final engine = _ttsEngine;
    if (state.speakingParagraphIndex == index) {
      engine?.stop();
      return;
    }
    if (engine == null || !engine.isAvailable()) {
      _unavailableTts();
      return;
    }
    final text = state.paragraphs[index].englishText;
    final id = engine.speak(text, speed: 0.70);
    if (id != null) {
      _currentUtteranceId = id;
      state = state.copyWith(speakingParagraphIndex: index);
    }
  }

  void _unavailableTts() {
    // Kotlin 会弹 Snackbar + 拉起系统设置；本任务无 Snackbar 通道，
    // 先置空说话状态，Task 24 接入完整提示。
    state = state.copyWith(speakingParagraphIndex: null);
  }

  @override
  void dispose() {
    _disposed = true;
    _readTimer?.cancel();
    for (final timer in _revealTimers) {
      timer.cancel();
    }
    _revealTimers.clear();
    _ttsEngine?.stop();
    _ttsEngine?.setOnSpeakingFinished(null);
    super.dispose();
  }
}

/// Reading 控制器 Provider（正文/译文/计时；播放条与查词弹窗在 Task 24 扩展）。
final readingControllerProvider = StateNotifierProvider.autoDispose
    .family<ReadingController, ReadingUiState, int>((ref, articleId) {
  return ReadingController(
    articleRepository: ref.watch(articleRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    vocabularyRepository: ref.watch(vocabularyRepositoryProvider),
    statsRepository: ref.watch(statsRepositoryProvider),
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
  );
});
