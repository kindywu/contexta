import 'package:drift/drift.dart';

import '../database.dart';

/// Task 11 DAO 词库组。
///
/// 对照 Android 原版 DAO 逐方法实现：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/dao/
///   WordDao.kt / WordSenseDao.kt / ExampleSentenceDao.kt / VocabularyEntryDao.kt
///
/// 插入冲突策略与 Kotlin 完全一致：
/// - word 表：IGNORE（spelling_normalized 唯一，重复插入返回 -1）
/// - word_sense / example_sentence / vocabulary_entry：REPLACE（按主键覆盖）

/// word 表 DAO。
/// 对照 WordDao.kt：getByNormalized/insert(IGNORE)/getById/getByIds。
class WordDao {
  WordDao(this._db);

  final AppDatabase _db;

  Future<WordRow?> getByNormalized(String normalized) =>
      (_db.select(_db.words)..where((t) => t.spellingNormalized.equals(normalized)))
          .getSingleOrNull();

  /// IGNORE 语义：spelling_normalized 重复时返回 -1（与 Kotlin Room
  /// OnConflictStrategy.IGNORE 的 -1 语义一致，仓储层依赖此值做 fallback）。
  Future<int> insert(WordsCompanion word) async {
    final affected = await _db.customUpdate(
      'INSERT OR IGNORE INTO word '
      '(spelling_normalized, spelling_display, phonetic_ipa) VALUES (?, ?, ?)',
      variables: [
        Variable(word.spellingNormalized.value),
        Variable(word.spellingDisplay.value),
        Variable(word.phoneticIpa.value),
      ],
      updates: {_db.words},
    );
    if (affected == 0) return -1;
    final row = await _db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
    return row.read<int>('id');
  }

  Future<WordRow?> getById(int id) =>
      (_db.select(_db.words)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<WordRow>> getByIds(List<int> ids) =>
      (_db.select(_db.words)..where((t) => t.id.isIn(ids))).get();
}

/// word_sense 表 DAO。
/// 对照 WordSenseDao.kt：getByWord/getPrimarySense/insertAll(REPLACE)/insert(REPLACE)。
class WordSenseDao {
  WordSenseDao(this._db);

  final AppDatabase _db;

  Future<List<WordSenseRow>> getByWord(int wordId) =>
      (_db.select(_db.wordSenses)
            ..where((t) => t.wordId.equals(wordId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  Future<WordSenseRow?> getPrimarySense(int wordId) =>
      (_db.select(_db.wordSenses)
            ..where((t) => t.wordId.equals(wordId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)])
            ..limit(1))
          .getSingleOrNull();

  /// REPLACE 语义批量插入，返回每行 id（与输入顺序一致）。
  /// Kotlin 仓储层用返回值定位 senseId 关联例句，故不能走 batch（batch 不返回 id）。
  Future<List<int>> insertAll(List<WordSensesCompanion> senses) async {
    final ids = <int>[];
    await _db.transaction(() async {
      for (final sense in senses) {
        ids.add(await _db.into(_db.wordSenses).insertOnConflictUpdate(sense));
      }
    });
    return ids;
  }

  Future<int> insert(WordSensesCompanion sense) =>
      _db.into(_db.wordSenses).insertOnConflictUpdate(sense);
}

/// example_sentence 表 DAO。
/// 对照 ExampleSentenceDao.kt：getBySense/insertAll(REPLACE)。
class ExampleSentenceDao {
  ExampleSentenceDao(this._db);

  final AppDatabase _db;

  Future<List<ExampleSentenceRow>> getBySense(int senseId) =>
      (_db.select(_db.exampleSentences)
            ..where((t) => t.wordSenseId.equals(senseId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  Future<void> insertAll(List<ExampleSentencesCompanion> sentences) =>
      _db.batch((b) =>
          b.insertAll(_db.exampleSentences, sentences, mode: InsertMode.replace));
}

/// vocabulary_entry 表 DAO。
/// 对照 VocabularyEntryDao.kt：getActiveByWord/observeActive/getActive/
/// insert(REPLACE)/nextInstanceNumber/markCorrectReview/markMastered/
/// resetStreak/softDelete/getById/countDistinctWords。
class VocabularyEntryDao {
  VocabularyEntryDao(this._db);

  final AppDatabase _db;

  /// 某词当前有效的生词条目（未删除、非 MASTERED），取 instance_number 最大。
  Future<VocabularyEntryRow?> getActiveByWord(int wordId) =>
      (_db.select(_db.vocabularyEntries)
            ..where((t) =>
                t.wordId.equals(wordId) &
                t.deletedAt.isNull() &
                t.status.equals('MASTERED').not())
            ..orderBy([(t) => OrderingTerm.desc(t.instanceNumber)])
            ..limit(1))
          .getSingleOrNull();

  Stream<List<VocabularyEntryRow>> observeActive() =>
      (_db.select(_db.vocabularyEntries)
            ..where((t) => t.deletedAt.isNull() & t.status.equals('MASTERED').not())
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch();

  Future<List<VocabularyEntryRow>> getActive() =>
      (_db.select(_db.vocabularyEntries)
            ..where((t) => t.deletedAt.isNull() & t.status.equals('MASTERED').not())
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Future<int> insert(VocabularyEntriesCompanion entry) =>
      _db.into(_db.vocabularyEntries).insertOnConflictUpdate(entry);

  /// COALESCE(MAX(instance_number), 0) + 1。
  Future<int> nextInstanceNumber(int wordId) async {
    final t = _db.vocabularyEntries;
    final maxExpr = t.instanceNumber.max();
    final rows = await (_db.selectOnly(t)
          ..addColumns([maxExpr])
          ..where(t.wordId.equals(wordId)))
        .get();
    return (rows.first.read(maxExpr) ?? 0) + 1;
  }

  /// streak +1 用 SQL 表达式（correct_review_streak = correct_review_streak + 1，
  /// 与 Kotlin 一致），故走 custom() 写原始表达式。
  Future<void> markCorrectReview(int id, String status) =>
      (_db.update(_db.vocabularyEntries)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .write(VocabularyEntriesCompanion.custom(
        status: Constant(status),
        correctReviewStreak:
            _db.vocabularyEntries.correctReviewStreak + Constant(1),
      ));

  Future<void> markMastered(int id, String now) =>
      (_db.update(_db.vocabularyEntries)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .write(VocabularyEntriesCompanion.custom(
        status: const Constant('MASTERED'),
        masteredAt: Constant(now),
        correctReviewStreak:
            _db.vocabularyEntries.correctReviewStreak + Constant(1),
      ));

  Future<void> resetStreak(int id) =>
      (_db.update(_db.vocabularyEntries)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .write(const VocabularyEntriesCompanion(correctReviewStreak: Value(0)));

  Future<void> softDelete(int id, String reason, String now) =>
      (_db.update(_db.vocabularyEntries)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .write(VocabularyEntriesCompanion(
        deletedAt: Value(now),
        deletedReason: Value(reason),
      ));

  Future<VocabularyEntryRow?> getById(int id) =>
      (_db.select(_db.vocabularyEntries)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<int> countDistinctWords() async {
    final t = _db.vocabularyEntries;
    final countExpr = t.wordId.count(distinct: true);
    final rows = await (_db.selectOnly(t)
          ..addColumns([countExpr])
          ..where(t.deletedAt.isNull()))
        .get();
    return rows.first.read(countExpr)!;
  }
}
