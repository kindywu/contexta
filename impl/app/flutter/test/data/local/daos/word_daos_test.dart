import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/word_daos.dart';

/// Task 11 DAO 词库组测试。
///
/// 对照 Android 原版 DAO（WordDao.kt / WordSenseDao.kt /
/// ExampleSentenceDao.kt / VocabularyEntryDao.kt）逐方法验证语义，
/// 重点是软删除、instance_number 递增、spelling_normalized 唯一。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WordDao', () {
    late AppDatabase db;
    late WordDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = WordDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('insert(IGNORE) 后 getByNormalized/getById/getByIds 可读', () async {
      final id = await dao.insert(WordsCompanion.insert(
        spellingNormalized: 'hello',
        spellingDisplay: 'hello',
        phoneticIpa: const Value('/həˈloʊ/'),
      ));
      expect(id, greaterThan(0));

      final byNorm = await dao.getByNormalized('hello');
      expect(byNorm!.spellingDisplay, 'hello');
      expect(byNorm.phoneticIpa, '/həˈloʊ/');

      expect((await dao.getById(id))!.spellingNormalized, 'hello');
      expect(await dao.getById(999), isNull);

      final byIds = await dao.getByIds([id]);
      expect(byIds.map((w) => w.spellingNormalized), ['hello']);
    });

    test('spelling_normalized 唯一：重复插入被 IGNORE（返回 -1）', () async {
      await dao.insert(WordsCompanion.insert(
        spellingNormalized: 'hello',
        spellingDisplay: 'hello',
      ));
      final second = await dao.insert(WordsCompanion.insert(
        spellingNormalized: 'hello',
        spellingDisplay: 'Hello',
      ));
      expect(second, -1); // 冲突被忽略

      final all = await db.select(db.words).get();
      expect(all.length, 1);
      expect(all.first.spellingDisplay, 'hello');
    });

    test('大小写不同的 normalized 是不同的词', () async {
      await dao.insert(WordsCompanion.insert(
        spellingNormalized: 'apple',
        spellingDisplay: 'apple',
      ));
      await dao.insert(WordsCompanion.insert(
        spellingNormalized: 'Apple',
        spellingDisplay: 'Apple',
      ));
      expect((await db.select(db.words).get()).length, 2);
    });
  });

  group('WordSenseDao', () {
    late AppDatabase db;
    late WordDao wordDao;
    late WordSenseDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      wordDao = WordDao(db);
      dao = WordSenseDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newWord(String spelling) => wordDao.insert(WordsCompanion.insert(
          spellingNormalized: spelling,
          spellingDisplay: spelling,
        ));

    WordSensesCompanion sense(int wordId, int orderIndex,
            {String pos = 'n.', String zh = '意思', String en = 'meaning'}) =>
        WordSensesCompanion.insert(
          wordId: wordId,
          orderIndex: orderIndex,
          partOfSpeech: pos,
          chineseMeaning: zh,
          englishDefinition: en,
        );

    test('insertAll 返回每行 id，顺序与输入一致', () async {
      final wordId = await newWord('run');
      final ids = await dao.insertAll([
        sense(wordId, 0),
        sense(wordId, 1, pos: 'v.', zh: '跑步'),
      ]);
      expect(ids.length, 2);
      expect(ids[0], greaterThan(0));
      expect(ids[1], greaterThan(ids[0]));

      final rows = await dao.getByWord(wordId);
      expect(rows.map((s) => s.orderIndex), [0, 1]);
      expect(rows.first.partOfSpeech, 'n.');
      expect(rows[1].chineseMeaning, '跑步');
    });

    test('getPrimarySense 取 order_index 最小的一条', () async {
      final wordId = await newWord('run');
      await dao.insert(sense(wordId, 1));
      await dao.insert(sense(wordId, 0, zh: '主要义'));

      final primary = await dao.getPrimarySense(wordId);
      expect(primary!.chineseMeaning, '主要义');
    });

    test('insert REPLACE：指定相同 id 覆盖旧行', () async {
      final wordId = await newWord('run');
      final id = await dao.insert(sense(wordId, 0, zh: '旧义'));
      await dao.insert(WordSensesCompanion(
        id: Value(id),
        wordId: Value(wordId),
        orderIndex: const Value(0),
        partOfSpeech: const Value('n.'),
        chineseMeaning: const Value('新义'),
        englishDefinition: const Value('new'),
      ));
      final rows = await dao.getByWord(wordId);
      expect(rows.length, 1);
      expect(rows.first.chineseMeaning, '新义');
    });
  });

  group('ExampleSentenceDao', () {
    late AppDatabase db;
    late WordDao wordDao;
    late WordSenseDao senseDao;
    late ExampleSentenceDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      wordDao = WordDao(db);
      senseDao = WordSenseDao(db);
      dao = ExampleSentenceDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('insertAll 后 getBySense 按 order_index 升序', () async {
      final wordId = await wordDao.insert(WordsCompanion.insert(
        spellingNormalized: 'see',
        spellingDisplay: 'see',
      ));
      final senseId = await senseDao.insert(WordSensesCompanion.insert(
        wordId: wordId,
        orderIndex: 0,
        partOfSpeech: 'v.',
        chineseMeaning: '看见',
        englishDefinition: 'to perceive with the eyes',
      ));

      await dao.insertAll([
        ExampleSentencesCompanion.insert(
          wordSenseId: senseId,
          orderIndex: 1,
          sentenceEn: 'I see you.',
          sentenceZh: '我看见你。',
          isPrimary: false,
        ),
        ExampleSentencesCompanion.insert(
          wordSenseId: senseId,
          orderIndex: 0,
          sentenceEn: 'See the bird.',
          sentenceZh: '看那只鸟。',
          isPrimary: true,
        ),
      ]);

      final sentences = await dao.getBySense(senseId);
      expect(sentences.map((s) => s.orderIndex), [0, 1]);
      expect(sentences.first.isPrimary, true);
      expect(sentences.first.sentenceEn, 'See the bird.');
    });

    test('不同 sense 的例句互不影响', () async {
      final wordId = await wordDao.insert(WordsCompanion.insert(
        spellingNormalized: 'see',
        spellingDisplay: 'see',
      ));
      final s1 = await senseDao.insert(WordSensesCompanion.insert(
        wordId: wordId,
        orderIndex: 0,
        partOfSpeech: 'v.',
        chineseMeaning: '看见',
        englishDefinition: 'to perceive',
      ));
      final s2 = await senseDao.insert(WordSensesCompanion.insert(
        wordId: wordId,
        orderIndex: 1,
        partOfSpeech: 'v.',
        chineseMeaning: '明白',
        englishDefinition: 'to understand',
      ));

      await dao.insertAll([
        ExampleSentencesCompanion.insert(
          wordSenseId: s1,
          orderIndex: 0,
          sentenceEn: 'a',
          sentenceZh: '一',
          isPrimary: false,
        ),
        ExampleSentencesCompanion.insert(
          wordSenseId: s2,
          orderIndex: 0,
          sentenceEn: 'b',
          sentenceZh: '二',
          isPrimary: false,
        ),
      ]);

      expect((await dao.getBySense(s1)).length, 1);
      expect((await dao.getBySense(s2)).first.sentenceEn, 'b');
    });
  });

  group('VocabularyEntryDao', () {
    late AppDatabase db;
    late WordDao wordDao;
    late VocabularyEntryDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      wordDao = WordDao(db);
      dao = VocabularyEntryDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newWord(String spelling) async =>
        await wordDao.insert(WordsCompanion.insert(
          spellingNormalized: spelling,
          spellingDisplay: spelling,
        ));

    Future<int> newEntry(int wordId, {String status = 'NEW', String? deletedAt}) =>
        dao.insert(VocabularyEntriesCompanion.insert(
          wordId: wordId,
          instanceNumber: 1,
          status: status,
          correctReviewStreak: 0,
          deletedAt: Value(deletedAt),
        ));

    test('insert / getActiveByWord / getById / nextInstanceNumber', () async {
      final wordId = await newWord('apple');
      final entryId = await dao.insert(VocabularyEntriesCompanion.insert(
        wordId: wordId,
        instanceNumber: 1,
        status: 'NEW',
        correctReviewStreak: 0,
      ));

      expect((await dao.getById(entryId))!.status, 'NEW');
      expect((await dao.getActiveByWord(wordId))!.id, entryId);
      expect(await dao.getActiveByWord(999), isNull);

      // 下一次 instance_number 递增
      expect(await dao.nextInstanceNumber(wordId), 2);
      await dao.insert(VocabularyEntriesCompanion.insert(
        wordId: wordId,
        instanceNumber: 2,
        status: 'NEW',
        correctReviewStreak: 0,
      ));
      expect(await dao.nextInstanceNumber(wordId), 3);
      // 无记录的词从 1 开始
      final other = await newWord('banana');
      expect(await dao.nextInstanceNumber(other), 1);
    });

    test('getActiveByWord 排除软删除与 MASTERED，取 instance_number 最大', () async {
      final wordId = await newWord('apple');
      await dao.insert(VocabularyEntriesCompanion.insert(
        wordId: wordId,
        instanceNumber: 1,
        status: 'MASTERED',
        correctReviewStreak: 0,
      ));
      await dao.insert(VocabularyEntriesCompanion.insert(
        wordId: wordId,
        instanceNumber: 2,
        status: 'NEW',
        correctReviewStreak: 0,
      ));
      final activeId = await dao.insert(VocabularyEntriesCompanion.insert(
        wordId: wordId,
        instanceNumber: 3,
        status: 'NEW',
        correctReviewStreak: 0,
      ));

      // MASTERED 的 instance 1 被排除，取最新的 active
      expect((await dao.getActiveByWord(wordId))!.id, activeId);

      // 软删除后不再 active
      await dao.softDelete(activeId, 'MANUAL_REMOVAL', '2026-08-07T10:00:00+08:00');
      expect((await dao.getActiveByWord(wordId))!.instanceNumber, 2);
    });

    test('getActive / observeActive 排除软删除与 MASTERED，按 id 升序', () async {
      final w1 = await newWord('apple');
      final w2 = await newWord('banana');
      await newEntry(w1);
      await newEntry(w2, deletedAt: '2026-08-07T10:00:00+08:00');
      await newEntry(w2);

      final active = await dao.getActive();
      expect(active.length, 2);
      expect(active.map((e) => e.wordId), [w1, w2]);

      final watched = await dao.observeActive().first;
      expect(watched.length, 2);

      // MASTERED 也排除
      final mastered = await newEntry(w1, status: 'MASTERED');
      expect((await dao.getActive()).length, 2);
      expect((await dao.getActive()).map((e) => e.id), isNot(contains(mastered)));
    });

    test('markCorrectReview：streak+1 并更新状态', () async {
      final wordId = await newWord('apple');
      final entryId = await newEntry(wordId);

      await dao.markCorrectReview(entryId, 'LEARNING');
      var entry = await dao.getById(entryId);
      expect(entry!.status, 'LEARNING');
      expect(entry.correctReviewStreak, 1);

      await dao.markCorrectReview(entryId, 'LEARNING');
      entry = await dao.getById(entryId);
      expect(entry!.correctReviewStreak, 2);
    });

    test('markMastered：状态 + mastered_at + streak+1', () async {
      final wordId = await newWord('apple');
      final entryId = await newEntry(wordId);

      await dao.markMastered(entryId, '2026-08-07T10:00:00+08:00');
      final entry = await dao.getById(entryId);
      expect(entry!.status, 'MASTERED');
      expect(entry.masteredAt, '2026-08-07T10:00:00+08:00');
      expect(entry.correctReviewStreak, 1);

      // 已 MASTERED 不再出现在 active
      expect(await dao.getActiveByWord(wordId), isNull);
    });

    test('resetStreak：streak 清零但状态不变', () async {
      final wordId = await newWord('apple');
      final entryId = await newEntry(wordId);
      await dao.markCorrectReview(entryId, 'LEARNING');
      await dao.markCorrectReview(entryId, 'LEARNING');

      await dao.resetStreak(entryId);
      final entry = await dao.getById(entryId);
      expect(entry!.correctReviewStreak, 0);
      expect(entry.status, 'LEARNING');
    });

    test('softDelete：deleted_at/reason 写入，active 查询排除', () async {
      final wordId = await newWord('apple');
      final entryId = await newEntry(wordId);

      await dao.softDelete(entryId, 'MANUAL_REMOVAL', '2026-08-07T10:00:00+08:00');
      // getById 本身带 deleted_at IS NULL 条件，直接查表验证写入
      final row = await (db.select(db.vocabularyEntries)
            ..where((t) => t.id.equals(entryId)))
          .getSingleOrNull();
      expect(row!.deletedAt, '2026-08-07T10:00:00+08:00');
      expect(row.deletedReason, 'MANUAL_REMOVAL');

      expect(await dao.getActiveByWord(wordId), isNull);
      expect((await dao.getActive()).length, 0);
      // getById 只返回未删除的
      expect(await dao.getById(entryId), isNull);
    });

    test('countDistinctWords：只统计未删除的词', () async {
      final w1 = await newWord('apple');
      final w2 = await newWord('banana');
      await newEntry(w1);
      await newEntry(w1); // 同词多条只计 1
      await newEntry(w2);
      final w3 = await newWord('cherry');
      final w3Entry = await newEntry(w3);

      expect(await dao.countDistinctWords(), 3);

      await dao.softDelete(w3Entry, 'MANUAL_REMOVAL', '2026-08-07T10:00:00+08:00');
      expect(await dao.countDistinctWords(), 2);
    });
  });
}
