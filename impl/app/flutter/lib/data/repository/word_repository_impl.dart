import 'dart:async';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';

import '../../data/local/database.dart';
import '../../data/local/daos/word_daos.dart';
import '../../domain/model/word_detail.dart';
import '../../domain/repository/word_repository.dart';

/// 词库仓储实现（对照 Kotlin WordRepositoryImpl.kt）。
///
/// 三层查词：
/// 1. LRU 缓存（LinkedHashMap 手动实现，上限 50，访问序淘汰最旧）
/// 2. 本地 DB（word + word_sense + example_sentence 组装 WordDetail）
/// 3. [llmFallback] 外部提供的 LLM 调用 → saveLlmResult 落库 → 缓存
///
/// 并发：lookupWord 用信号量限制同时进行的查词数（permits = 3）。
class WordRepositoryImpl implements WordRepository {
  WordRepositoryImpl(
    this._wordDao,
    this._wordSenseDao,
    this._exampleSentenceDao,
    this._vocabularyEntryDao,
  );

  final WordDao _wordDao;
  final WordSenseDao _wordSenseDao;
  final ExampleSentenceDao _exampleSentenceDao;
  final VocabularyEntryDao _vocabularyEntryDao;

  /// LRU 缓存：按访问序淘汰最旧条目，上限 50。
  final _lruCache = _LruCache<String, WordDetail>(50);

  /// 查词并发限制（对照 Kotlin Semaphore(3)）。
  final _lookupSemaphore = _Semaphore(3);

  @override
  Future<WordDetail?> lookupWord(
      String spelling, Future<WordDetail?> Function(String) llmFallback) {
    return _lookupSemaphore.withPermit(() async {
      final normalized = WordRepository.normalize(spelling);
      debugPrint('[WordRepo] lookupWord "$normalized"');

      // 1. LRU 缓存
      final cached = _lruCache[normalized];
      if (cached != null) {
        debugPrint('[WordRepo] LRU HIT "$normalized"');
        return cached;
      }

      // 2. 本地 DB
      final existing = await _wordDao.getByNormalized(normalized);
      if (existing != null) {
        debugPrint('[WordRepo] DB HIT "$normalized" id=${existing.id}');
        final detail = await _buildWordDetail(existing);
        _lruCache[normalized] = detail;
        return detail;
      }
      debugPrint('[WordRepo] DB MISS "$normalized" → LLM fallback');

      // 3. LLM fallback（外部提供调用）；成功后落库回填
      final detail = await llmFallback(spelling);
      if (detail != null) {
        debugPrint('[WordRepo] LLM fallback OK "$normalized" wordId=${detail.wordId}');
        _lruCache[normalized] = detail;
      } else {
        debugPrint('[WordRepo] LLM fallback returned null "$normalized"');
      }
      return detail;
    });
  }

  @override
  Future<WordDetail?> findLocal(String spelling) async {
    final normalized = WordRepository.normalize(spelling);
    final cached = _lruCache[normalized];
    if (cached != null) return cached;
    final existing = await _wordDao.getByNormalized(normalized);
    if (existing == null) return null;
    final detail = await _buildWordDetail(existing);
    _lruCache[normalized] = detail;
    return detail;
  }

  @override
  Future<WordDetail> saveLlmResult(
    String spellingDisplay,
    String? phoneticIpa,
    List<WordSense> senses, {
    String? normalized,
  }) async {
    final norm = normalized ?? WordRepository.normalize(spellingDisplay);

    // word 表 IGNORE 语义：冲突（已存在）时复用已有行
    final insertedId = await _wordDao.insert(WordsCompanion.insert(
      spellingNormalized: norm,
      spellingDisplay: spellingDisplay,
      phoneticIpa: Value(phoneticIpa),
    ));
    final wordId = insertedId == -1
        ? (await _wordDao.getByNormalized(norm))!.id
        : insertedId;

    // senses：order_index <= 0 用序号；insertAll 返回每行 id
    final senseEntities = <WordSensesCompanion>[];
    for (var i = 0; i < senses.length; i++) {
      final sense = senses[i];
      senseEntities.add(WordSensesCompanion.insert(
        wordId: wordId,
        orderIndex: sense.orderIndex > 0 ? sense.orderIndex : i,
        partOfSpeech: sense.partOfSpeech,
        chineseMeaning: sense.chineseMeaning,
        englishDefinition: sense.englishDefinition,
      ));
    }
    final senseIds = await _wordSenseDao.insertAll(senseEntities);

    for (var i = 0; i < senseEntities.length; i++) {
      final sense = senses[i];
      final senseId = senseIds[i];
      final exampleEntities = <ExampleSentencesCompanion>[];
      for (var exIndex = 0; exIndex < sense.examples.length; exIndex++) {
        final ex = sense.examples[exIndex];
        exampleEntities.add(ExampleSentencesCompanion.insert(
          wordSenseId: senseId,
          orderIndex: ex.orderIndex > 0 ? ex.orderIndex : exIndex,
          sentenceEn: ex.sentenceEn,
          sentenceZh: ex.sentenceZh,
          isPrimary: ex.isPrimary,
        ));
      }
      if (exampleEntities.isNotEmpty) {
        await _exampleSentenceDao.insertAll(exampleEntities);
      }
    }

    final word = await _wordDao.getById(wordId);
    if (word == null) {
      throw StateError('Failed to read back word $wordId');
    }
    final detail = await _buildWordDetail(word);
    _lruCache[norm] = detail;
    return detail;
  }

  @override
  Future<WordDetail?> getWordDetail(int wordId) async {
    final word = await _wordDao.getById(wordId);
    if (word == null) return null;
    return _buildWordDetail(word);
  }

  @override
  Future<Map<int, WordDetail>> getWordDetails(List<int> wordIds) async {
    final words = await _wordDao.getByIds(wordIds);
    final result = <int, WordDetail>{};
    for (final word in words) {
      result[word.id] = await _buildWordDetail(word);
    }
    return result;
  }

  @override
  Future<void> invalidateCache(String spelling) {
    _lruCache.remove(WordRepository.normalize(spelling));
    return Future.value();
  }

  /// 组装完整 WordDetail（senses + examples + 生词本状态）。
  Future<WordDetail> _buildWordDetail(WordRow word) async {
    final senseRows = await _wordSenseDao.getByWord(word.id);
    final senseModels = <WordSense>[];
    for (final sense in senseRows) {
      final examples = await _exampleSentenceDao.getBySense(sense.id);
      senseModels.add(WordSense(
        id: sense.id,
        orderIndex: sense.orderIndex,
        partOfSpeech: sense.partOfSpeech,
        chineseMeaning: sense.chineseMeaning,
        englishDefinition: sense.englishDefinition,
        examples: examples
            .map((ex) => ExampleSentence(
                  id: ex.id,
                  orderIndex: ex.orderIndex,
                  sentenceEn: ex.sentenceEn,
                  sentenceZh: ex.sentenceZh,
                  isPrimary: ex.isPrimary,
                ))
            .toList(),
      ));
    }

    final vocabEntry = await _vocabularyEntryDao.getActiveByWord(word.id);
    return WordDetail(
      wordId: word.id,
      spellingDisplay: word.spellingDisplay,
      phoneticIpa: word.phoneticIpa,
      primarySense: senseModels.isEmpty ? null : senseModels.first,
      allSenses: senseModels,
      isInVocabulary: vocabEntry != null,
      vocabularyEntryId: vocabEntry?.id,
    );
  }
}

/// 最小 LRU 实现（访问序，上限 [capacity]）。
class _LruCache<K, V> {
  _LruCache(this.capacity);

  final int capacity;
  final _map = <K, V>{};

  V? operator [](K key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value; // 移到末尾（最近访问）
    return value;
  }

  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > capacity) {
      _map.remove(_map.keys.first); // 淘汰最旧
    }
  }

  V? remove(K key) => _map.remove(key);

  int get length => _map.length;
}

/// 最小信号量（对照 Kotlin Semaphore(3)）：并发超限时排队等待。
class _Semaphore {
  _Semaphore(this.permits);

  final int permits;
  int _taken = 0;
  final _queue = <void Function()>[];

  Future<T> withPermit<T>(Future<T> Function() action) {
    if (_taken < permits) {
      _taken++;
      return _run(action);
    }
    final completer = Completer<void>();
    _queue.add(completer.complete);
    return completer.future.then((_) {
      _taken++;
      return _run(action);
    });
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      _taken--;
      if (_queue.isNotEmpty) {
        _queue.removeAt(0)();
      }
    }
  }
}
