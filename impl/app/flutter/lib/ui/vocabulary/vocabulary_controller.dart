import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/model/vocab_word.dart';
import '../../domain/repository/settings_repository.dart';
import '../../domain/repository/vocabulary_repository.dart';
import '../../domain/tts/tts_engine.dart';

/// Vocabulary 页 UI 状态（对照 Kotlin VocabularyUiState）。
class VocabularyUiState {
  const VocabularyUiState({
    this.totalCount = 0,
    this.currentIndex = 0,
    this.currentWord,
    this.isLoading = true,
    this.isSummary = false,
    this.reviewedCount = 0,
    this.newlyKnownCount = 0,
  });

  final int totalCount;
  final int currentIndex;
  final VocabCardData? currentWord;
  final bool isLoading;

  /// 全部复习完（总结页）。
  final bool isSummary;
  final int reviewedCount;

  /// 本轮新标记「认识」并达阈值转为 MASTERED 的词数。
  final int newlyKnownCount;

  VocabularyUiState copyWith({
    int? totalCount,
    int? currentIndex,
    Object? currentWord = _unset,
    bool? isLoading,
    bool? isSummary,
    int? reviewedCount,
    int? newlyKnownCount,
  }) =>
      VocabularyUiState(
        totalCount: totalCount ?? this.totalCount,
        currentIndex: currentIndex ?? this.currentIndex,
        currentWord: identical(currentWord, _unset)
            ? this.currentWord
            : currentWord as VocabCardData?,
        isLoading: isLoading ?? this.isLoading,
        isSummary: isSummary ?? this.isSummary,
        reviewedCount: reviewedCount ?? this.reviewedCount,
        newlyKnownCount: newlyKnownCount ?? this.newlyKnownCount,
      );

  static const Object _unset = Object();
}

/// 卡片数据（对照 Kotlin VocabCardData）。
class VocabCardData {
  const VocabCardData({
    required this.entryId,
    required this.word,
    this.phonetic,
    this.senses = const [],
    this.reviewStreak = 0,
    this.masteryThreshold = 1,
  });

  final int entryId;
  final String word;
  final String? phonetic;
  final List<VocabSenseData> senses;
  final int reviewStreak;
  final int masteryThreshold;
}

/// 词性块数据（对照 Kotlin VocabSenseData）。
class VocabSenseData {
  const VocabSenseData({
    required this.partOfSpeech,
    required this.chineseMeaning,
    required this.englishDefinition,
    this.examples = const [],
  });

  final String partOfSpeech;
  final String chineseMeaning;
  final String englishDefinition;
  final List<VocabExampleData> examples;
}

/// 例句数据（对照 Kotlin VocabExampleData）。
class VocabExampleData {
  const VocabExampleData({
    required this.sentenceEn,
    required this.sentenceZh,
  });

  final String sentenceEn;
  final String sentenceZh;
}

/// Vocabulary 页控制器（对照 Kotlin VocabularyViewModel）：
/// - 进入页面加载设置（masteryThreshold + autoPlayAudio）+ 生词列表（打乱）
/// - 显示当前词卡片；autoPlayAudio 开启时自动朗读（TTS 不可用静默跳过）
/// - markCorrect/markIncorrect：记录 + 达阈值自动转 MASTERED（从列表移除，
///   newlyKnownCount+1）；goNext/goPrevious 无判定切换
/// - 全部复习完 → 总结页（复习单词数 / 新标记认识数 / 再来一轮）
class VocabularyController extends StateNotifier<VocabularyUiState> {
  VocabularyController({
    required this._vocabularyRepository,
    required this._settingsRepository,
    required Future<TtsEngine> ttsEngineFuture,
  })  : _ttsEngineFuture = ttsEngineFuture,
        super(const VocabularyUiState()) {
    ttsEngineFuture.then(_onTtsReady);
    loadVocabulary();
  }

  final VocabularyRepository _vocabularyRepository;
  final SettingsRepository _settingsRepository;
  final Future<TtsEngine> _ttsEngineFuture;

  TtsEngine? _ttsEngine;
  List<VocabWord> _vocabList = [];
  int _masteryThreshold = 1;
  bool _autoPlayAudio = false;
  bool _disposed = false;

  void _onTtsReady(TtsEngine engine) {
    if (_disposed) {
      engine.stop();
      return;
    }
    _ttsEngine = engine;
  }

  Future<void> loadVocabulary() async {
    final settings = await _settingsRepository.getSettings();
    _masteryThreshold = settings?.masteryThresholdN ?? 1;
    _autoPlayAudio = settings?.autoPlayAudio ?? false;

    final words = (await _vocabularyRepository.getActiveWords()).toList()
      ..shuffle();
    _vocabList = words;

    if (words.isEmpty) {
      state = const VocabularyUiState(isLoading: false);
    } else {
      _showWordAt(0);
    }
  }

  void _showWordAt(int index) {
    if (index >= _vocabList.length) {
      state = state.copyWith(
        isSummary: true,
        currentWord: null,
      );
      return;
    }
    final item = _vocabList[index];
    // 达阈值转 MASTERED 的词已从列表移除：total = 剩余 + 已掌握
    final masteredCount = state.totalCount - _vocabList.length;
    final total = masteredCount > 0 ? state.totalCount : _vocabList.length;

    state = VocabularyUiState(
      totalCount: total,
      currentIndex: index,
      currentWord: VocabCardData(
        entryId: item.entryId,
        word: item.spellingDisplay,
        phonetic: item.phoneticIpa,
        senses: [
          for (final sense in item.allSenses)
            VocabSenseData(
              partOfSpeech: sense.partOfSpeech,
              chineseMeaning: sense.chineseMeaning,
              englishDefinition: sense.englishDefinition,
              examples: [
                for (final example in sense.examples)
                  VocabExampleData(
                    sentenceEn: example.sentenceEn,
                    sentenceZh: example.sentenceZh,
                  ),
              ],
            ),
        ],
        reviewStreak: item.correctReviewStreak,
        masteryThreshold: _masteryThreshold,
      ),
      isLoading: false,
      reviewedCount: state.reviewedCount,
      newlyKnownCount: state.newlyKnownCount,
    );

    // 自动朗读：设置开启时每显示一个新单词自动朗读（TTS 不可用静默跳过；
    // 引擎未就绪则等待——Kotlin 注入的引擎已就绪，这里对齐该语义）
    if (_autoPlayAudio) {
      unawaited(_autoPlayWord(item.spellingDisplay));
    }
  }

  Future<void> _autoPlayWord(String word) async {
    var engine = _ttsEngine;
    if (engine == null) {
      try {
        engine = await _ttsEngineFuture;
      } catch (_) {
        return;
      }
      if (_disposed) return;
    }
    if (!engine.isAvailable()) return;
    engine.speak(word);
  }

  /// 标记认识：streak+1；达阈值自动转 MASTERED（从列表移除）。
  Future<void> markCorrect() async {
    final current = state.currentWord;
    if (current == null) return;
    await _vocabularyRepository
        .markCorrect(current.entryId, masteryThreshold: _masteryThreshold);

    // 判断是否已掌握（已从活跃列表移除）
    final stillActive = await _vocabularyRepository.getActiveWords();
    final wasMastered = !stillActive.any((w) => w.entryId == current.entryId);

    if (wasMastered) {
      _vocabList = _vocabList.where((w) => w.entryId != current.entryId).toList();
      state = state.copyWith(
        newlyKnownCount: state.newlyKnownCount + 1,
        reviewedCount: state.reviewedCount + 1,
      );
    } else {
      state = state.copyWith(reviewedCount: state.reviewedCount + 1);
    }
    _advanceToNext();
  }

  /// 标记不认识：重置 streak。
  Future<void> markIncorrect() async {
    final current = state.currentWord;
    if (current == null) return;
    await _vocabularyRepository.markIncorrect(current.entryId);
    state = state.copyWith(reviewedCount: state.reviewedCount + 1);
    _advanceToNext();
  }

  /// 无判定切换（滑动到下一个/上一个）。
  void goNext() => _advanceToNext();

  void goPrevious() {
    final prev = state.currentIndex - 1;
    if (prev >= 0) {
      _showWordAt(prev);
    }
  }

  void _advanceToNext() {
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= _vocabList.length) {
      state = state.copyWith(
        isSummary: true,
        currentWord: null,
      );
    } else {
      _showWordAt(nextIndex);
    }
  }

  void playWord() {
    final word = state.currentWord?.word;
    if (word == null) return;
    _ttsEngine?.speak(word);
  }

  /// 重新开始一轮复习。
  void restart() {
    state = const VocabularyUiState();
    loadVocabulary();
  }

  @override
  void dispose() {
    _disposed = true;
    _ttsEngine?.stop();
    super.dispose();
  }
}

/// Vocabulary 页控制器 Provider。
final vocabularyControllerProvider =
    StateNotifierProvider.autoDispose<VocabularyController, VocabularyUiState>(
        (ref) {
  return VocabularyController(
    vocabularyRepository: ref.watch(vocabularyRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    ttsEngineFuture: ref.watch(ttsEngineProvider.future),
  );
});
