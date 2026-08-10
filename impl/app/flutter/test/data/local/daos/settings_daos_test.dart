import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/core/time/iso8601.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/settings_daos.dart';
import 'package:contexta/data/repository/settings_repository_impl.dart';
import 'package:contexta/domain/model/tts_voice.dart';

/// Task 9 DAO 基础组测试。
///
/// 对照 Android 原版 DAO（UserSettingsDao.kt / DailyLearningDao.kt /
/// LearningStatsSummaryDao.kt / ConfigChangeLogDao.kt /
/// SchemaMigrationLogDao.kt / GenerationPipelineStatusDao.kt /
/// DailyLearningLogDao.kt）逐方法验证语义。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserSettingsDao', () {
    late AppDatabase db;
    late UserSettingsDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = UserSettingsDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('无记录时 get 返回 null', () async {
      expect(await dao.get(), isNull);
    });

    test('upsert 后 get 可读（id=1 单例）', () async {
      await dao.upsert(const UserSettingsCompanion(
        id: Value(1),
        isOnboarded: Value(true),
        difficultyLevel: Value('MEDIUM'),
        dailyArticleCount: Value(5),
        translationDisplayMode: Value('FULL'),
        ttsSpeed: Value(1.0),
        ttsVoiceId: Value('BELLA'),
        masteryThresholdN: Value(2),
        autoPlayAudio: Value(true),
      ));
      final row = await dao.get();
      expect(row, isNotNull);
      expect(row!.id, 1);
      expect(row.isOnboarded, true);
      expect(row.dailyArticleCount, 5);
      expect(row.masteryThresholdN, 2);
      expect(row.autoPlayAudio, true);
    });

    test('markOnboarded 置位 is_onboarded=1', () async {
      await dao.upsert(const UserSettingsCompanion(
        id: Value(1),
        isOnboarded: Value(false),
        difficultyLevel: Value('MEDIUM'),
        dailyArticleCount: Value(3),
        translationDisplayMode: Value('FULL'),
        ttsSpeed: Value(1.0),
        ttsVoiceId: Value('BELLA'),
        masteryThresholdN: Value(1),
        autoPlayAudio: Value(false),
      ));
      await dao.markOnboarded();
      final row = await dao.get();
      expect(row!.isOnboarded, true);
    });
  });

  group('SettingsRepository', () {
    late AppDatabase db;
    late UserSettingsDao dao;
    late SettingsRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = UserSettingsDao(db);
      repo = SettingsRepositoryImpl(dao);
    });

    tearDown(() async {
      await db.close();
    });

    test('updateTtsVoice 持久化后读回，无行默认 BELLA', () async {
      await repo.completeOnboarding('MEDIUM', 3);
      // completeOnboarding 默认行 tts_voice_id = 'BELLA'
      expect((await repo.getSettings())!.ttsVoice, TtsVoice.bella);

      await repo.updateTtsVoice(TtsVoice.hugo);
      final settings = await repo.getSettings();
      expect(settings!.ttsVoice, TtsVoice.hugo);
      final row = await dao.get();
      expect(row!.ttsVoiceId, 'HUGO');
    });

    test('无行时不抛错（与 updateTtsSpeed 行为一致）', () async {
      await repo.updateTtsVoice(TtsVoice.leo); // 空库，无 user_settings 行
    });
  });

  group('DailyLearningDao', () {
    late AppDatabase db;
    late DailyLearningDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = DailyLearningDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('空表 getAll / getLatest / getMaxRefBatchDate 返回空', () async {
      expect(await dao.getAll(), isEmpty);
      expect(await dao.getLatest(), isNull);
      expect(await dao.getMaxRefBatchDate(), isNull);
    });

    test('insert 后按日期降序返回，ref_batch_id 外键生效', () async {
      // 先插入一个批次（daily_learning 有 FK → article_batch）
      final batchId = await db.into(db.articleBatches).insert(ArticleBatchesCompanion.insert(
            difficultyLevelSnapshot: 'LOW',
            status: 'READY',
            generatedOn: '2026-03-29',
            lastUpdatedAt: isoOffsetDateTime(DateTime(2026, 3, 29, 12, 0)),
          ));

      await dao.insert(DailyLearningsCompanion.insert(
        learningDate: '2026-08-01',
        refBatchDate: '2026-03-29',
        refBatchId: batchId,
        dailyCountSnapshot: 3,
      ));
      await dao.insert(DailyLearningsCompanion.insert(
        learningDate: '2026-08-02',
        refBatchDate: '2026-03-29',
        refBatchId: batchId,
        dailyCountSnapshot: 3,
      ));

      final all = await dao.getAll();
      expect(all.map((r) => r.learningDate), ['2026-08-02', '2026-08-01']);
      expect((await dao.getLatest())!.learningDate, '2026-08-02');
      expect((await dao.getByLearningDate('2026-08-01'))!.learningDate, '2026-08-01');
      expect(await dao.getByLearningDate('2026-08-03'), isNull);
      expect(await dao.getMaxRefBatchDate(), '2026-03-29');
    });

    test('insert 同一天重复抛约束异常（learning_date 主键 ABORT）', () async {
      final batchId = await db.into(db.articleBatches).insert(ArticleBatchesCompanion.insert(
            difficultyLevelSnapshot: 'LOW',
            status: 'READY',
            generatedOn: '2026-03-29',
            lastUpdatedAt: isoOffsetDateTime(DateTime(2026, 3, 29, 12, 0)),
          ));
      await dao.insert(DailyLearningsCompanion.insert(
        learningDate: '2026-08-01',
        refBatchDate: '2026-03-29',
        refBatchId: batchId,
        dailyCountSnapshot: 3,
      ));
      expect(
        () => dao.insert(DailyLearningsCompanion.insert(
          learningDate: '2026-08-01',
          refBatchDate: '2026-03-29',
          refBatchId: batchId,
          dailyCountSnapshot: 3,
        )),
        throwsA(isA<SqliteException>()),
      );
      expect((await dao.getAll()).length, 1);
    });
  });

  group('LearningStatsSummaryDao', () {
    late AppDatabase db;
    late LearningStatsSummaryDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = LearningStatsSummaryDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('空表 get 返回 null；upsert 后可读', () async {
      expect(await dao.get(), isNull);
      await dao.upsert(const LearningStatsSummariesCompanion(
        id: Value(1),
        totalArticlesRead: Value(4),
        totalWordsAdded: Value(7),
        totalWordsMastered: Value(2),
        totalLearningDays: Value(3),
        currentStreak: Value(2),
        longestStreak: Value(5),
        lastActiveDate: Value('2026-08-06'),
      ));
      final row = await dao.get();
      expect(row!.totalArticlesRead, 4);
      expect(row.totalWordsAdded, 7);
      expect(row.currentStreak, 2);
      expect(row.lastActiveDate, '2026-08-06');
    });
  });

  group('ConfigChangeLogDao', () {
    late AppDatabase db;
    late ConfigChangeLogDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = ConfigChangeLogDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('countToday / countThisMonth 按时间窗口统计', () async {
      await dao.insert(ConfigChangeLogsCompanion.insert(
        fieldName: 'daily_article_count',
        oldValue: '3',
        newValue: '5',
        createdAt: '2026-08-06T10:00:00+08:00',
      ));
      await dao.insert(ConfigChangeLogsCompanion.insert(
        fieldName: 'daily_article_count',
        oldValue: '5',
        newValue: '3',
        createdAt: '2026-08-01T10:00:00+08:00',
      ));
      await dao.insert(ConfigChangeLogsCompanion.insert(
        fieldName: 'daily_article_count',
        oldValue: '3',
        newValue: '5',
        createdAt: '2026-07-01T10:00:00+08:00',
      ));

      // 2026-08-06 当天
      final dayStart = DateTime(2026, 8, 6).millisecondsSinceEpoch;
      final dayEnd = DateTime(2026, 8, 7).millisecondsSinceEpoch;
      expect(await dao.countToday('daily_article_count', dayStart, dayEnd), 1);

      // 2026-08 整月
      final monthStart = DateTime(2026, 8, 1).millisecondsSinceEpoch;
      final monthEnd = DateTime(2026, 9, 1).millisecondsSinceEpoch;
      expect(await dao.countThisMonth('daily_article_count', monthStart, monthEnd), 2);

      // 其他字段名不计入
      expect(await dao.countToday('other_field', dayStart, dayEnd), 0);
    });
  });

  group('SchemaMigrationLogDao', () {
    late AppDatabase db;
    late SchemaMigrationLogDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = SchemaMigrationLogDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('getLatest / getCurrentVersion 取最新一条', () async {
      expect(await dao.getLatest(), isNull);
      expect(await dao.getCurrentVersion(), isNull);

      await dao.insert(SchemaMigrationLogsCompanion.insert(
        fromVersion: 0,
        toVersion: 1,
        description: 'init',
        createdAt: '2026-08-01T10:00:00+08:00',
      ));
      await dao.insert(SchemaMigrationLogsCompanion.insert(
        fromVersion: 1,
        toVersion: 2,
        description: 'add column',
        createdAt: '2026-08-02T10:00:00+08:00',
      ));

      final latest = await dao.getLatest();
      expect(latest!.toVersion, 2);
      expect(await dao.getCurrentVersion(), 2);
    });
  });

  group('GenerationPipelineStatusDao', () {
    late AppDatabase db;
    late GenerationPipelineStatusDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = GenerationPipelineStatusDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsert / clearBlocked / setBlocked', () async {
      expect(await dao.get(), isNull);

      await dao.upsert(const GenerationPipelineStatusesCompanion(
        id: Value(1),
        isBlocked: Value(true),
        blockedReason: Value('structural'),
        blockedAt: Value('2026-08-06T10:00:00+08:00'),
        blockedAppVersionCode: Value(2),
      ));
      var row = await dao.get();
      expect(row!.isBlocked, true);
      expect(row.blockedReason, 'structural');

      await dao.setBlocked(
        reason: 'fatal',
        now: '2026-08-06T11:00:00+08:00',
        appVersionCode: 3,
      );
      row = await dao.get();
      expect(row!.isBlocked, true);
      expect(row.blockedReason, 'fatal');
      expect(row.blockedAppVersionCode, 3);

      await dao.clearBlocked();
      row = await dao.get();
      expect(row!.isBlocked, false);
    });
  });

  group('DailyLearningLogDao', () {
    late AppDatabase db;
    late DailyLearningLogDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = DailyLearningLogDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsert REPLACE + addActivity/addWordActivity 累加', () async {
      await dao.upsert(DailyLearningLogsCompanion.insert(
        logDate: '2026-08-06',
        articlesRead: 0,
        wordsAdded: 0,
        secondsSpent: 0,
      ));
      var row = await dao.getByDate('2026-08-06');
      expect(row!.articlesRead, 0);
      expect(row.secondsSpent, 0);

      await dao.addActivity('2026-08-06', 2, 300);
      await dao.addWordActivity('2026-08-06');
      row = await dao.getByDate('2026-08-06');
      expect(row!.articlesRead, 2);
      expect(row.secondsSpent, 300);
      expect(row.wordsAdded, 1);

      // 与 Kotlin 一致：log_date 无 UNIQUE 约束，upsert(REPLACE) 按主键 id 冲突，
      // 同日重复 upsert 会插入第二行（原版语义由调用方先 getByDate 判空保证）。
      // getByDate 对重复行抛 "Too many elements"（与 Kotlin 单行查询语义一致）。
      await dao.upsert(DailyLearningLogsCompanion.insert(
        logDate: '2026-08-06',
        articlesRead: 5,
        wordsAdded: 0,
        secondsSpent: 0,
      ));
      final all = await db.select(db.dailyLearningLogs).get();
      expect(all.length, 2);
      expect(
        () => dao.getByDate('2026-08-06'),
        throwsA(isA<StateError>()),
      );
    });

    test('countActiveDays / getActiveDates 只统计有活动的日期', () async {
      await dao.upsert(DailyLearningLogsCompanion.insert(
        logDate: '2026-08-01',
        articlesRead: 0,
        wordsAdded: 0,
        secondsSpent: 0,
      ));
      await dao.addActivity('2026-08-01', 1, 0);
      await dao.upsert(DailyLearningLogsCompanion.insert(
        logDate: '2026-08-02',
        articlesRead: 0,
        wordsAdded: 0,
        secondsSpent: 0,
      ));
      await dao.upsert(DailyLearningLogsCompanion.insert(
        logDate: '2026-08-03',
        articlesRead: 0,
        wordsAdded: 0,
        secondsSpent: 0,
      ));
      await dao.addWordActivity('2026-08-03');

      expect(await dao.countActiveDays(), 2);
      expect(await dao.getActiveDates(), ['2026-08-03', '2026-08-01']);
    });
  });
}
