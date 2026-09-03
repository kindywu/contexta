import 'dart:async';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';

import '../../data/local/database.dart';
import '../../data/local/daos/word_daos.dart';
import '../../domain/inflection/inflection_resolver.dart';
import '../../domain/model/word_detail.dart';
import '../../domain/repository/word_repository.dart';

/// 词库仓储实现（对照 Kotlin WordRepositoryImpl.kt）。
///
/// 四层查词：
/// 1. LRU 缓存（LinkedHashMap 手动实现，上限 50，访问序淘汰最旧）
/// 2. 本地 DB（word + word_sense + example_sentence 组装 WordDetail）
/// 2.5 词形解析（精确 miss 后：规则引擎候选逐一查库，命中返回词条 + POS 标注）
/// 3. [llmFallback] 外部提供的 LLM 调用 → saveLlmResult 落库 → 缓存
///
/// 并发：lookupWord 用信号量限制同时进行的查词数（permits = 3）。
class WordRepositoryImpl implements WordRepository {
  WordRepositoryImpl(
    this._wordDao,
    this._wordSenseDao,
    this._exampleSentenceDao,
    this._vocabularyEntryDao, {
    this._inflectionResolver = const RuleInflectionResolver(),
  });

  final WordDao _wordDao;
  final WordSenseDao _wordSenseDao;
  final ExampleSentenceDao _exampleSentenceDao;
  final VocabularyEntryDao _vocabularyEntryDao;
  final InflectionResolver _inflectionResolver;

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
      debugPrint('[WordRepo] DB MISS "$normalized" → inflection → LLM fallback');

      // 2.5 词形解析：精确 miss 后，规则引擎候选逐一查库
      final withInflection = await _resolveWithInflection(normalized);
      if (withInflection != null) return withInflection;

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
    if (existing == null) {
      return _resolveWithInflection(normalized);
    }
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

  /// 词形解析：候选按序查库，返回第一个命中的 (词条行, 候选)。
  Future<(WordRow, InflectionCandidate)?> _resolveInflection(
      String normalized) async {
    for (final candidate in _inflectionResolver.resolveCandidates(normalized)) {
      final row = await _wordDao.getByNormalized(candidate.lemma);
      if (row != null) return (row, candidate);
    }
    return null;
  }

  /// 词形解析命中 → 组装带标注的 WordDetail 并缓存（key=原词）；未命中返回 null。
  /// lookupWord 与 findLocal 共用，保证两处解析链行为一致（含 INFLECTION HIT 日志）。
  Future<WordDetail?> _resolveWithInflection(String normalized) async {
    final resolved = await _resolveInflection(normalized);
    if (resolved == null) return null;
    final (wordRow, candidate) = resolved;
    debugPrint('[WordRepo] INFLECTION HIT "$normalized" → ${candidate.lemma} '
        '(${candidate.type.name}) id=${wordRow.id}');
    final detail = await _buildWordDetail(wordRow);
    final withInflection = detail.copyWith(
      inflection: InflectionResult(
        lemma: candidate.lemma,
        type: candidate.type,
        note: _inflectionNote(
            normalized, candidate.lemma, candidate.type, detail),
      ),
    );
    _lruCache[normalized] = withInflection;
    return withInflection;
  }

  /// 标注文案：sForm 按词元义项词性区分复数 / 第三人称单数。
  String _inflectionNote(
      String source, String lemma, InflectionType type, WordDetail detail) {
    switch (type) {
      case InflectionType.sForm:
        final pos = detail.allSenses.map((s) => s.partOfSpeech).toSet();
        // 词性首段精确匹配（I-1）：'n.'/'n' → 名词；'v.'/'vi.'/'vt.'/'v' → 动词。
        // 'adv.'（含 v）、'pron.'（含 n）、'det./pron.'、'r.'（WordNet 副词）等
        // 不以 n/v 开头，不会误判；'adv.' 以 a 开头，startsWith('v') 为 false。
        final hasNoun = pos.any((p) => p.split('.').first.trim() == 'n');
        final hasVerb = pos.any((p) => p.trim().startsWith('v'));
        if (hasNoun && hasVerb) return '$source 是 $lemma 的复数形式 / 第三人称单数';
        if (hasVerb) return '$source 是 $lemma 的第三人称单数形式';
        return '$source 是 $lemma 的复数形式';
      case InflectionType.pastTense:
        return '$source 是 $lemma 的过去式/过去分词';
      case InflectionType.presentParticiple:
        return '$source 是 $lemma 的现在分词';
      case InflectionType.comparative:
        return '$source 是 $lemma 的比较级';
      case InflectionType.superlative:
        return '$source 是 $lemma 的最高级';
    }
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
