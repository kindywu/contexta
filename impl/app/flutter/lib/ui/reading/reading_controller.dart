import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/generation/word_prompts.dart';
import '../../domain/llm_client.dart';
import '../../domain/model/article.dart';
import '../../domain/model/tts_voice.dart';
import '../../domain/model/word_detail.dart';
import '../../domain/repository/article_repository.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/repository/stats_repository.dart';
import '../../domain/repository/vocabulary_repository.dart';
import '../../domain/repository/word_repository.dart';
import '../../domain/tts/tts_engine.dart';
import '../../data/tts/kitten_tts_engine.dart';
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
    this.wordSheetData,
    this.isWordSheetVisible = false,
    this.snackbarMessage,
    this.openTtsSettings = false,
    this.ttsSpeed = 1.0,
    this.ttsVoice = TtsVoice.bella,
    this.isReadCompleted = false,
    this.isSpeakingFullArticle = false,
    this.speechProgress,
    this.speechTotalParagraphs,
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

  /// 查词弹窗数据（null = 未打开）。
  final WordSheetData? wordSheetData;
  final bool isWordSheetVisible;

  /// TTS 不可用提示（Snackbar 消费后经 [ReadingController.clearSnackbar] 清除）。
  final String? snackbarMessage;

  /// TTS 不可用时拉起系统 TTS 设置（UI 层消费）。
  final bool openTtsSettings;

  /// 显示语速（1x / 0.75x；引擎内部映射实际速率）。
  final double ttsSpeed;

  /// 朗读音色（设置页可选，进入文章时从设置读取）。
  final TtsVoice ttsVoice;
  final bool isReadCompleted;

  /// 全文朗读中。
  final bool isSpeakingFullArticle;

  /// 全文朗读播放进度（当前发声段落序号 1-based，标题段为 null）。
  final double? speechProgress;

  /// 全文朗读总段数（正文段数，配合 speechProgress 显示「第 N/M 段」）。
  final int? speechTotalParagraphs;

  /// 正在朗读的段落索引（null = 无）。
  final int? speakingParagraphIndex;

  static const Object _unset = Object();

  ReadingUiState copyWith({
    String? title,
    List<ArticleParagraph>? paragraphs,
    TranslationMode? translationMode,
    Set<int>? revealedParagraphs,
    Set<String>? vocabularyWords,
    bool? isLoading,
    String? error,
    Object? wordSheetData = _unset,
    bool? isWordSheetVisible,
    Object? snackbarMessage = _unset,
    bool? openTtsSettings,
    double? ttsSpeed,
    TtsVoice? ttsVoice,
    bool? isReadCompleted,
    bool? isSpeakingFullArticle,
    Object? speechProgress = _unset,
    Object? speechTotalParagraphs = _unset,
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
        wordSheetData: identical(wordSheetData, _unset)
            ? this.wordSheetData
            : wordSheetData as WordSheetData?,
        isWordSheetVisible: isWordSheetVisible ?? this.isWordSheetVisible,
        snackbarMessage: identical(snackbarMessage, _unset)
            ? this.snackbarMessage
            : snackbarMessage as String?,
        openTtsSettings: openTtsSettings ?? this.openTtsSettings,
        ttsSpeed: ttsSpeed ?? this.ttsSpeed,
        ttsVoice: ttsVoice ?? this.ttsVoice,
        isReadCompleted: isReadCompleted ?? this.isReadCompleted,
        isSpeakingFullArticle: isSpeakingFullArticle ?? this.isSpeakingFullArticle,
        speechProgress: identical(speechProgress, _unset)
            ? this.speechProgress
            : speechProgress as double?,
        speechTotalParagraphs: identical(speechTotalParagraphs, _unset)
            ? this.speechTotalParagraphs
            : speechTotalParagraphs as int?,
        speakingParagraphIndex: speakingParagraphIndex,
      );
}

/// 查词弹窗数据（对照 Kotlin WordSheetData）。
class WordSheetData {
  const WordSheetData({
    required this.word,
    this.isLoading = false,
    this.phonetic,
    this.senses = const [],
    this.isInVocabulary = false,
    this.wordId,
    this.vocabularyEntryId,
    this.inflectionNote,
  });

  final String word;
  final bool isLoading;
  final String? phonetic;
  final List<WordSenseUi> senses;
  final bool isInVocabulary;
  final int? wordId;
  final int? vocabularyEntryId;

  /// 词形解析标注（"homes 是 home 的复数形式"）。
  final String? inflectionNote;

  static const Object _unset = Object();

  /// Kotlin 语义的 data.copy：显式传 null 即置空（移出生词本时清 entryId）。
  WordSheetData copyWith({
    bool? isLoading,
    String? phonetic,
    List<WordSenseUi>? senses,
    bool? isInVocabulary,
    Object? wordId = _unset,
    Object? vocabularyEntryId = _unset,
    String? inflectionNote,
  }) =>
      WordSheetData(
        word: word,
        isLoading: isLoading ?? this.isLoading,
        phonetic: phonetic ?? this.phonetic,
        senses: senses ?? this.senses,
        isInVocabulary: isInVocabulary ?? this.isInVocabulary,
        wordId: identical(wordId, _unset) ? this.wordId : wordId as int?,
        vocabularyEntryId: identical(vocabularyEntryId, _unset)
            ? this.vocabularyEntryId
            : vocabularyEntryId as int?,
        inflectionNote: inflectionNote ?? this.inflectionNote,
      );
}

/// 词性分组后的单个义项。同词性义项在 [WordSheetData.senses] 中相邻排列。
class WordSenseUi {
  const WordSenseUi({
    required this.partOfSpeech,
    required this.englishDefinition,
    required this.chineseMeaning,
  });

  final String partOfSpeech;
  final String englishDefinition;
  final String chineseMeaning;
}

/// Reading 页控制器（对照 Kotlin ReadingViewModel）：
/// - loadArticle：getArticle → 设置（译文模式 + autoPlayAudio）→ 生词集合 →
///   自动朗读（TTS 不可用静默跳过）→ recordReadingActivity → 未读时启动 15s 计时
/// - 计时：15s tick addReadSeconds + tryMarkReadCompleted，达 120s 自动已读；
///   手动标记 forceMarkReadCompleted
/// - 译文模式循环 + BLURRED 点击揭示（10s 自动重新模糊）
/// - 播放：段落内联播放 / 全文朗读（互斥）+ 语速 1x↔0.75x + 单词发音；
///   当前 utterance 结束才清状态（id 校验过滤迟到旧事件）；TTS 不可用
///   → Snackbar + 拉起系统 TTS 设置（自动朗读静默跳过）
/// - 查词：showWordSheet 立即显示 loading → 三层查词（LRU→DB→LLM 落库）
///   → 成功回填 / 失败降级仅词头；加入/移除生词本即时更新高亮
class ReadingController extends StateNotifier<ReadingUiState> {
  ReadingController({
    required this._articleRepository,
    required this._settingsRepository,
    required this._vocabularyRepository,
    required this._statsRepository,
    required this._wordRepository,
    required this._llmClient,
    required Future<TtsEngine> ttsEngineFuture,
  })  : _ttsEngineFuture = ttsEngineFuture,
        super(const ReadingUiState()) {
    // TTS 引擎由 FutureProvider 异步初始化（KittenTTS 模型加载）；就绪后
    // 替换引擎并注册完成回调，期间朗读静默跳过（同 Kotlin 自动朗读语义）
    ttsEngineFuture.then(_onTtsReady);
  }

  static const String ttsErrorMessage = '语音引擎未安装，请在系统设置中开启「文字转语音」功能';

  final ArticleRepository _articleRepository;
  final SettingsRepository _settingsRepository;
  final VocabularyRepository _vocabularyRepository;
  final StatsRepository _statsRepository;
  final WordRepository _wordRepository;
  final LlmClient _llmClient;
  final Future<TtsEngine> _ttsEngineFuture;

  TtsEngine? _ttsEngine;

  /// 防止全文朗读启动期间重复点击。
  bool _startingPlayback = false;

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
      debugPrint('[ReadingCtrl] onSpeakingFinished: id=$utteranceId current=$_currentUtteranceId');
      if (utteranceId == _currentUtteranceId) {
        _currentUtteranceId = null;
        if (!_disposed) {
          state = state.copyWith(
            isSpeakingFullArticle: false,
            speakingParagraphIndex: null,
            speechProgress: null,
            speechTotalParagraphs: null,
          );
          // 播放结束后预生成剩余段落缓存（引擎空闲，不抢占播放）
          _pregenerateParagraphs(state.paragraphs);
        }
      }
    });
    // 全文朗读段落级播放进度：播放 worker 每段发声前上报（KittenTTS 路径；
    // 系统 TTS 无段落边界不触发）。id 校验过滤迟到旧事件（同 finish 回调
    // 语义）。同时驱动播放条进度（第 N/M 段）——播放位置而非生成位置，
    // 标题段（-1）不显示段号。
    engine.setOnParagraphStarted((utteranceId, paragraphIndex, total) {
      debugPrint('[ReadingCtrl] paragraphStarted: id=$utteranceId index=$paragraphIndex total=$total current=$_currentUtteranceId');
      if (utteranceId == _currentUtteranceId && !_disposed) {
        state = state.copyWith(
          speakingParagraphIndex: paragraphIndex,
          speechProgress: paragraphIndex >= 0
              ? (paragraphIndex + 1).toDouble()
              : null,
          speechTotalParagraphs: paragraphIndex >= 0 ? total : null,
        );
      }
    });
    debugPrint('[ReadingCtrl] _onTtsReady: isKitten=${engine is KittenTtsEngine} runtimeType=${engine.runtimeType}');
    if (engine is KittenTtsEngine) {
      // 生成进度仅日志观测（播放条已改由 paragraphStarted 播放进度驱动，
      // 生成超前于发声，不可作为 UI 进度）
      engine.setOnProgress((utteranceId, done, total) {
        if (utteranceId == _currentUtteranceId && !_disposed) {
          debugPrint('[ReadingCtrl] genProgress: $done/$total');
        }
      });
    }
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
      // 全局语速/音色：进入文章时从设置读取（设置页可改，切换时回写）
      ttsSpeed: settings?.ttsSpeed ?? 1.0,
      ttsVoice: settings?.ttsVoice ?? TtsVoice.bella,
      revealedParagraphs: const {},
      isLoading: false,
      isReadCompleted: alreadyRead,
      vocabularyWords: vocabWords,
      // 切换文章时重置段落播放状态，防止上一篇文章的状态残留
      isSpeakingFullArticle: false,
      speakingParagraphIndex: null,
    );

    // 自动朗读：设置开启时进入文章自动播全文（TTS 不可用时静默跳过，不打扰用户）
    if (settings?.autoPlayAudio == true) {
      await startFullArticlePlayback();
    }
    // Record reading activity for stats
    await _statsRepository.recordReadingActivity();
    // Start timer to track reading duration
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

  /// 后台预生成段落 TTS 缓存（引擎空闲时调用，不抢占播放）。
  void _pregenerateParagraphs(List<ArticleParagraph> paragraphs) {
    final engine = _ttsEngine;
    if (engine is! KittenTtsEngine) return;
    unawaited(engine.pregenerateParagraphs(
      paragraphs: [
        for (final p in paragraphs)
          (paragraphId: p.id, text: p.englishText),
      ],
      speed: state.ttsSpeed,
      voice: state.ttsVoice,
    ));
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

  // ─── 播放（段落 / 全文 / 单词） ────────────────────────────────

  /// 朗读段落；再次点击正在朗读的段落停止。
  ///
  /// 引擎尚未初始化（KittenTTS 模型解压/下载中）时等待就绪后再朗读，
  /// 对齐 Kotlin 注入即就绪的 TTS 引擎语义；就绪后仍不可用才提示。
  Future<void> playParagraph(int index) async {
    debugPrint('[ReadingCtrl] playParagraph index=$index');
    if (state.speakingParagraphIndex == index) {
      _ttsEngine?.stop();
      return;
    }
    var engine = _ttsEngine;
    if (engine == null) {
      try {
        engine = await _ttsEngineFuture;
      } catch (_) {
        return;
      }
      if (_disposed) return;
    }
    if (!engine.isAvailable()) {
      _unavailableTts();
      return;
    }
    // 优先缓存：命中直接播文件；未命中生成 + 写缓存
    String? id;
    if (engine is KittenTtsEngine) {
      final p = state.paragraphs[index];
      id = await engine.speakParagraph(
        paragraphId: p.id,
        text: p.englishText,
        speed: state.ttsSpeed,
        voice: state.ttsVoice,
      );
    } else {
      id = engine.speak(state.paragraphs[index].englishText,
          speed: state.ttsSpeed, voice: state.ttsVoice);
    }
    if (id != null) {
      _currentUtteranceId = id;
      state = state.copyWith(
        isSpeakingFullArticle: false,
        speakingParagraphIndex: index,
      );
    }
  }

  /// 全文朗读开关：朗读中 → 停止；空闲 → 开始（TTS 不可用弹提示）。
  ///
  /// 引擎未就绪时等待就绪后开始（对齐 startFullArticlePlayback 与 Kotlin
  /// 注入即就绪的语义），避免 KittenTTS 首次初始化窗口误报不可用。
  Future<void> toggleFullArticlePlayback() async {
    debugPrint('[ReadingCtrl] toggleFullArticlePlayback isSpeaking=${state.isSpeakingFullArticle} starting=$_startingPlayback _ttsEngine=$_ttsEngine paragraphs=${state.paragraphs.length}');

    if (state.isSpeakingFullArticle) {
      _ttsEngine?.stop();
      _startingPlayback = false;
      state = state.copyWith(
        isSpeakingFullArticle: false,
        speechProgress: null,
        speechTotalParagraphs: null,
      );
      return;
    }
    // 启动中防重复点击
    if (_startingPlayback) {
      debugPrint('[ReadingCtrl] toggleFullArticlePlayback: already starting, skip');
      return;
    }

    // 点击瞬间立即设播放中 → 按钮立即变成暂停图标
    _startingPlayback = true;
    state = state.copyWith(isSpeakingFullArticle: true);
    debugPrint('[ReadingCtrl] toggleFullArticlePlayback: immediate state → speaking');

    var engine = _ttsEngine;
    if (engine == null) {
      debugPrint('[ReadingCtrl] engine null, waiting _ttsEngineFuture...');
      try {
        engine = await _ttsEngineFuture;
        debugPrint('[ReadingCtrl] engine future resolved: $engine');
      } catch (e) {
        debugPrint('[ReadingCtrl] engine future failed: $e');
        _startingPlayback = false;
        state = state.copyWith(isSpeakingFullArticle: false);
        return;
      }
      if (_disposed) { _startingPlayback = false; return; }
    }
    if (!engine.isAvailable()) {
      debugPrint('[ReadingCtrl] engine not available! reason=${engine.unavailabilityReason()}');
      _startingPlayback = false;
      state = state.copyWith(isSpeakingFullArticle: false);
      _unavailableTts();
      return;
    }
    final ok = await startFullArticlePlayback();
    if (!ok) {
      // 播放失败 → 回滚按钮状态
      _startingPlayback = false;
      state = state.copyWith(isSpeakingFullArticle: false);
    } else {
      _startingPlayback = false;
    }
  }

  /// 开始全文朗读（手动播放与自动朗读共用）。TTS 不可用时静默返回 false，
  /// 不弹提示（引擎初始化中则等待就绪）。
  ///
  /// 标题与正文单 utterance 无缝衔接：
  /// - KittenTTS：经 [KittenTtsEngine.speakFullArticle] 双 worker 流水线，
  ///   标题在前，逐段生成→播放，进度只计正文段落。
  /// - 系统 TTS：拼接「标题 + 正文」一段朗读。
  Future<bool> startFullArticlePlayback() async {
    debugPrint('[ReadingCtrl] startFullArticlePlayback ENTER');
    var engine = _ttsEngine;
    debugPrint('[ReadingCtrl] startFullArticlePlayback: _ttsEngine=$engine isAvailable=${engine?.isAvailable()}');
    if (engine == null) {
      debugPrint('[ReadingCtrl] engine null, waiting _ttsEngineFuture');
      try {
        engine = await _ttsEngineFuture;
        debugPrint('[ReadingCtrl] engine future resolved: $engine');
      } catch (e) {
        debugPrint('[ReadingCtrl] _ttsEngineFuture threw: $e');
        return false;
      }
      if (_disposed) return false;
    }
    if (!engine.isAvailable()) {
      debugPrint('[ReadingCtrl] engine not available! reason=${engine.unavailabilityReason()}');
      return false;
    }

    final title = state.title;
    final hasTitle = title != null && title.isNotEmpty;

    // KittenTTS：标题 + 正文单 utterance 无缝衔接（双 worker 流水线）
    if (engine is KittenTtsEngine) {
      final id = await engine.speakFullArticle(
        title: hasTitle ? title : null,
        paragraphs: [
          for (final p in state.paragraphs)
            (id: p.id, text: p.englishText),
        ],
        speed: state.ttsSpeed,
        voice: state.ttsVoice,
      );
      debugPrint('[ReadingCtrl] speakFullArticle returned: $id');
      if (id == null) {
        debugPrint('[ReadingCtrl] speakFullArticle returned null');
        return false;
      }
      _currentUtteranceId = id;
      state = state.copyWith(
        isSpeakingFullArticle: true,
        speakingParagraphIndex: null,
      );
      debugPrint('[ReadingCtrl] KITTEN FULLARTICLE PATH SUCCESS id=$id');
      return true;
    }

    // 系统 TTS 等：拼接全文（含标题）走统一接口
    final parts = <String>[
      if (title != null && title.isNotEmpty) title,
      for (final p in state.paragraphs) p.englishText,
    ];
    final fullText = parts.join(' ');
    debugPrint('[ReadingCtrl] speaking full text: len=${fullText.length} speed=${state.ttsSpeed}');
    final id = engine.speak(fullText, speed: state.ttsSpeed, voice: state.ttsVoice);
    debugPrint('[ReadingCtrl] engine.speak returned: $id');
    if (id == null) {
      debugPrint('[ReadingCtrl] engine.speak returned null');
      return false;
    }
    _currentUtteranceId = id;
    state = state.copyWith(
      isSpeakingFullArticle: true,
      speakingParagraphIndex: null,
    );
    debugPrint('[ReadingCtrl] FALLBACK PATH SUCCESS id=$id');
    return true;
  }

  /// 朗读查词弹窗中的单词（打断段落/全文播放）。
  void playWordPronunciation() {
    final word = state.wordSheetData?.word;
    debugPrint('[ReadingCtrl] playWordPronunciation word="$word"');
    if (word == null) return;
    final engine = _ttsEngine;
    debugPrint('[ReadingCtrl] playWordPronunciation engine=$engine available=${engine?.isAvailable()}');
    if (engine == null || !engine.isAvailable()) {
      _unavailableTts();
      return;
    }
    final id = engine.speak(word, speed: state.ttsSpeed, voice: state.ttsVoice);
    debugPrint('[ReadingCtrl] playWordPronunciation speak returned id=$id');
    if (id != null) {
      _currentUtteranceId = id;
      state = state.copyWith(
        isSpeakingFullArticle: false,
        speakingParagraphIndex: null,
      );
    }
  }

  /// 语速切换：1x → 0.8x → 1.2x → 1x 循环（引擎内部把显示语速映射为实际速率）。
  /// 切换结果回写设置（全局生效，设置页同步显示）。
  void toggleTtsSpeed() {
    const speeds = [1.0, 0.8, 1.2];
    final current = state.ttsSpeed;
    final nextIndex = speeds.indexOf(current);
    final next = nextIndex >= 0
        ? speeds[(nextIndex + 1) % speeds.length]
        : speeds.first;
    state = state.copyWith(ttsSpeed: next);
    _settingsRepository.updateTtsSpeed(next);
  }

  void _unavailableTts() {
    state = state.copyWith(
      snackbarMessage: ttsErrorMessage,
      openTtsSettings: true,
    );
  }

  /// Snackbar 展示后清除（同时复位拉起设置的标记）。
  void clearSnackbar() {
    state = state.copyWith(snackbarMessage: null, openTtsSettings: false);
  }

  // ─── 查词弹窗 ─────────────────────────────────────────────────

  /// 打开查词弹窗：立即显示 loading，异步三层查词后回填。
  void showWordSheet(String word) {
    final normalized = WordRepository.normalize(word);
    state = state.copyWith(
      wordSheetData: WordSheetData(word: normalized, isLoading: true),
      isWordSheetVisible: true,
    );
    unawaited(_lookupWord(normalized));
  }

  Future<void> _lookupWord(String normalized) async {
    WordDetail? detail;
    try {
      detail = await _wordRepository.lookupWord(normalized, _llmFallback);
    } catch (e) {
      debugPrint('[ReadingCtrl] _lookupWord ERROR: $e');
      detail = null;
    }
    if (_disposed) return;
    if (detail != null) {
      state = state.copyWith(
        wordSheetData: WordSheetData(
          // 解析命中显示原词（homes），精确命中显示词条 spellingDisplay（保持现状）
          word: detail.inflection == null ? detail.spellingDisplay : normalized,
          isLoading: false,
          phonetic: detail.phoneticIpa,
          senses: _groupSensesByPartOfSpeech(detail.allSenses),
          isInVocabulary: detail.isInVocabulary,
          wordId: detail.wordId,
          vocabularyEntryId: detail.vocabularyEntryId,
          inflectionNote: detail.inflection?.note,
        ),
        isWordSheetVisible: true,
      );
    } else {
      // 降级：仅词头，无义项（对照 Kotlin）
      state = state.copyWith(
        wordSheetData: WordSheetData(
          word: normalized,
          isLoading: false,
          isInVocabulary: false,
        ),
        isWordSheetVisible: true,
      );
    }
  }

  /// LLM 兜底查词：DeepSeek 生成 → 解析 → 落库回填（返回带 DB ID 的详情）。
  Future<WordDetail?> _llmFallback(String rawWord) async {
    debugPrint('[ReadingCtrl] _llmFallback: calling LLM for "$rawWord"');
    try {
      final result = await _llmClient.call(
        await buildWordLookupSystemPrompt(),
        buildWordLookupUserPrompt(rawWord),
      );
      debugPrint('[ReadingCtrl] _llmFallback: LLM content len=${result.content.length} retries=${result.retryCount}');
      final parsed = parseWordLlmResponse(result.content);
      if (parsed == null) {
        debugPrint('[ReadingCtrl] _llmFallback: PARSE FAILED. content: ${result.content}');
        return null;
      }
      return _wordRepository.saveLlmResult(
        parsed.spellingDisplay,
        parsed.phoneticIpa,
        parsed.allSenses,
        normalized: WordRepository.normalize(parsed.spellingDisplay),
      );
    } catch (e) {
      debugPrint('[ReadingCtrl] _llmFallback ERROR: $e');
      return null;
    }
  }

  /// 按词性分组（组序 = 义项首次出现序，保留语境匹配义项优先），
  /// 同词性义项相邻排列（对照 Kotlin groupSensesByPartOfSpeech）。
  static List<WordSenseUi> _groupSensesByPartOfSpeech(List<WordSense> senses) {
    final byPos = <String, List<WordSense>>{};
    for (final sense in senses) {
      byPos.putIfAbsent(sense.partOfSpeech, () => []).add(sense);
    }
    return [
      for (final entry in byPos.entries)
        for (final sense in entry.value)
          WordSenseUi(
            partOfSpeech: entry.key,
            englishDefinition: sense.englishDefinition,
            chineseMeaning: sense.chineseMeaning,
          ),
    ];
  }

  void hideWordSheet() {
    state = state.copyWith(
      isWordSheetVisible: false,
      wordSheetData: null,
    );
  }

  /// 加入生词本：更新弹窗数据与正文高亮（即时生效）。
  Future<void> addToVocabulary() async {
    final wordId = state.wordSheetData?.wordId;
    final word = state.wordSheetData?.word;
    if (wordId == null || word == null) return;
    final entryId = await _vocabularyRepository.addWord(wordId);
    if (entryId != null) {
      await _statsRepository.recordWordAdded();
      await _wordRepository.invalidateCache(word);
    }
    state = state.copyWith(
      wordSheetData: state.wordSheetData?.copyWith(
        isInVocabulary: entryId != null,
        vocabularyEntryId: entryId,
      ),
      vocabularyWords: entryId != null
          ? {...state.vocabularyWords, word}
          : state.vocabularyWords,
    );
  }

  /// 从生词本移除（软删除，记录原因）。
  Future<void> removeFromVocabulary() async {
    final entryId = state.wordSheetData?.vocabularyEntryId;
    final word = state.wordSheetData?.word;
    if (entryId == null || word == null) return;
    await _vocabularyRepository.removeWord(entryId);
    await _wordRepository.invalidateCache(word);
    state = state.copyWith(
      wordSheetData: state.wordSheetData?.copyWith(
        isInVocabulary: false,
        vocabularyEntryId: null,
      ),
      vocabularyWords: {...state.vocabularyWords}..remove(word),
    );
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

/// Reading 控制器 Provider。
final readingControllerProvider = StateNotifierProvider.autoDispose
    .family<ReadingController, ReadingUiState, int>((ref, articleId) {
  return ReadingController(
    articleRepository: ref.watch(articleRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    vocabularyRepository: ref.watch(vocabularyRepositoryProvider),
    statsRepository: ref.watch(statsRepositoryProvider),
    wordRepository: ref.watch(wordRepositoryProvider),
    llmClient: ref.watch(llmClientProvider),
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
  );
});
