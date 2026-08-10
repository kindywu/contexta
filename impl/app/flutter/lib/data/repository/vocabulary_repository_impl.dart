import 'package:drift/drift.dart' hide isNull, isNotNull;

import '../../domain/model/vocab_word.dart';
import '../../domain/repository/vocabulary_repository.dart';
import '../../domain/repository/word_repository.dart';
import '../local/database.dart';
import '../local/daos/word_daos.dart';

/// 生词本仓储实现（对照 Kotlin VocabularyRepositoryImpl.kt）。
class VocabularyRepositoryImpl implements VocabularyRepository {
  VocabularyRepositoryImpl(
    this._entryDao,
    this._wordRepository,
    this._nowIso,
  );

  final VocabularyEntryDao _entryDao;
  final WordRepository _wordRepository;

  /// 当前时间（ISO 8601 偏移字符串），注入以便测试固定时钟。
  final String Function() _nowIso;

  @override
  Stream<List<VocabWord>> observeActive() =>
      _entryDao.observeActive().asyncMap((entries) async {
        final result = <VocabWord>[];
        for (final entry in entries) {
          final detail = await _wordRepository.getWordDetail(entry.wordId);
          if (detail == null) continue;
          result.add(VocabWord(
            entryId: entry.id,
            wordId: entry.wordId,
            instanceNumber: entry.instanceNumber,
            status: VocabStatus.fromDbValue(entry.status),
            correctReviewStreak: entry.correctReviewStreak,
            spellingDisplay: detail.spellingDisplay,
            phoneticIpa: detail.phoneticIpa,
            allSenses: detail.allSenses,
          ));
        }
        return result;
      });

  @override
  Future<int> getActiveCount() async =>
      (await _entryDao.getActive()).length;

  @override
  Future<List<VocabWord>> getActiveWords() async {
    final entries = await _entryDao.getActive();
    final result = <VocabWord>[];
    for (final entry in entries) {
      final detail = await _wordRepository.getWordDetail(entry.wordId);
      if (detail == null) continue;
      result.add(VocabWord(
        entryId: entry.id,
        wordId: entry.wordId,
        instanceNumber: entry.instanceNumber,
        status: VocabStatus.fromDbValue(entry.status),
        correctReviewStreak: entry.correctReviewStreak,
        spellingDisplay: detail.spellingDisplay,
        phoneticIpa: detail.phoneticIpa,
        allSenses: detail.allSenses,
      ));
    }
    return result;
  }

  @override
  Future<int?> addWord(int wordId) async {
    final existing = await _entryDao.getActiveByWord(wordId);
    if (existing != null) return null;

    final nextInstance = await _entryDao.nextInstanceNumber(wordId);
    return _entryDao.insert(VocabularyEntriesCompanion(
      wordId: Value(wordId),
      instanceNumber: Value(nextInstance),
      status: const Value('NEW'),
      correctReviewStreak: const Value(0),
    ));
  }

  @override
  Future<void> markCorrect(int entryId, {int masteryThreshold = 1}) async {
    if (masteryThreshold <= 1) {
      await _entryDao.markMastered(entryId, _nowIso());
    } else {
      await _entryDao.markCorrectReview(entryId, 'LEARNING');
      final entry = await _entryDao.getById(entryId);
      if (entry != null && entry.correctReviewStreak >= masteryThreshold) {
        await _entryDao.markMastered(entryId, _nowIso());
      }
    }
  }

  @override
  Future<void> markIncorrect(int entryId) =>
      _entryDao.resetStreak(entryId);

  @override
  Future<void> removeWord(int entryId, {String reason = 'MANUAL_REMOVAL'}) =>
      _entryDao.softDelete(entryId, reason, _nowIso());

  @override
  Future<int> countDistinctWords() => _entryDao.countDistinctWords();
}
