import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';

/// Task 10 DAO 文章组测试。
///
/// 对照 Android 原版 DAO（ArticleBatchDao.kt / ArticleDao.kt /
/// ArticleParagraphDao.kt / GenerationErrorLogDao.kt）逐方法验证语义，
/// 重点是 CAS 认领（claimForGeneration）与中断恢复（认 GENERATING）语义。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArticleBatchDao', () {
    late AppDatabase db;
    late ArticleBatchDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = ArticleBatchDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertBatch({
      required String status,
      required String difficulty,
      required String generatedOn,
      String? lastUpdatedAt,
      String? blockedReason,
      String? blockedAt,
      int? readyNotifiedAt,
    }) {
      return db.into(db.articleBatches).insert(ArticleBatchesCompanion.insert(
            status: status,
            difficultyLevelSnapshot: difficulty,
            generatedOn: generatedOn,
            lastUpdatedAt: lastUpdatedAt ?? '2026-08-01T10:00:00+08:00',
            blockedReason: Value(blockedReason),
            blockedAt: Value(blockedAt),
            readyNotifiedAt: Value(readyNotifiedAt),
          ));
    }

    test('getById / getByDifficultyAndDate', () async {
      final id1 = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-03-29');
      await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-03-30');
      await insertBatch(
          status: 'READY', difficulty: 'MEDIUM', generatedOn: '2026-03-29');

      final byId = await dao.getById(id1);
      expect(byId!.generatedOn, '2026-03-29');
      expect(await dao.getById(999), isNull);

      // 同难度同日期取 id 最大的一条
      final byDiff = await dao.getByDifficultyAndDate('LOW', '2026-03-30');
      expect(byDiff!.generatedOn, '2026-03-30');
      expect(await dao.getByDifficultyAndDate('LOW', '2026-01-01'), isNull);
    });

    test('findNextReadyBatch：afterDate null 返回最早 READY；严格晚于已消费日期', () async {
      await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-03-29');
      final later = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-04-05');
      await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-04-10');

      // 首次使用：返回最早 READY 批次
      expect((await dao.findNextReadyBatch('LOW', null))!.generatedOn, '2026-03-29');
      // 严格大于 afterDate（不回头分配）
      expect((await dao.findNextReadyBatch('LOW', '2026-03-29'))!.id, later);
      expect(await dao.findNextReadyBatch('LOW', '2026-04-10'), isNull);
      // 难度不匹配
      expect(await dao.findNextReadyBatch('MEDIUM', null), isNull);
    });

    test('findNextReadyBatch：已被 daily_learning 引用的批次不返回', () async {
      final consumed = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-03-29');
      await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-04-05');

      await db.into(db.dailyLearnings).insert(DailyLearningsCompanion.insert(
            learningDate: '2026-08-01',
            refBatchDate: '2026-03-29',
            refBatchId: consumed,
            dailyCountSnapshot: 3,
          ));

      expect((await dao.findNextReadyBatch('LOW', null))!.generatedOn, '2026-04-05');
    });

    test('claimForGeneration CAS：PENDING/GENERATING 可认领，READY 不可', () async {
      final pendingId = await insertBatch(
          status: 'PENDING', difficulty: 'LOW', generatedOn: '2026-08-01');
      final generatingId = await insertBatch(
          status: 'GENERATING', difficulty: 'LOW', generatedOn: '2026-08-02');
      final readyId = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-08-03');

      expect(await dao.claimForGeneration(pendingId, '2026-08-07T09:00:00+08:00'), 1);
      expect(await dao.claimForGeneration(generatingId, '2026-08-07T09:00:00+08:00'), 1);
      expect(await dao.claimForGeneration(readyId, '2026-08-07T09:00:00+08:00'), 0);
    });

    test('updateStatus / markBlocked / getGeneratingBatches / resetAllGeneratingBatches', () async {
      final id = await insertBatch(
          status: 'PENDING', difficulty: 'LOW', generatedOn: '2026-08-01');
      final blockedId = await insertBatch(
          status: 'BLOCKED',
          difficulty: 'LOW',
          generatedOn: '2026-08-02',
          blockedReason: 'structural',
          blockedAt: '2026-08-02T10:00:00+08:00');

      await dao.updateStatus(id, 'READY', '2026-08-07T09:00:00+08:00');
      expect((await dao.getById(id))!.status, 'READY');

      await dao.markBlocked(blockedId, 'fatal', '2026-08-07T09:00:00+08:00');
      final blocked = await dao.getById(blockedId);
      expect(blocked!.status, 'BLOCKED');
      expect(blocked.blockedReason, 'fatal');
      expect(blocked.blockedAt, '2026-08-07T09:00:00+08:00');

      final genId = await insertBatch(
          status: 'GENERATING', difficulty: 'LOW', generatedOn: '2026-08-03');
      expect((await dao.getGeneratingBatches()).map((b) => b.id), [genId]);

      await dao.resetAllGeneratingBatches();
      expect(await dao.getGeneratingBatches(), isEmpty);
      expect((await dao.getById(genId))!.status, 'PENDING');
    });

    test('getReadyBatches / getUnassignedReadyBatches', () async {
      final consumed = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-03-29');
      await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-04-05');
      await insertBatch(
          status: 'PENDING', difficulty: 'LOW', generatedOn: '2026-04-10');

      await db.into(db.dailyLearnings).insert(DailyLearningsCompanion.insert(
            learningDate: '2026-08-01',
            refBatchDate: '2026-03-29',
            refBatchId: consumed,
            dailyCountSnapshot: 3,
          ));

      // getReadyBatches 含已消费批次
      final ready = await dao.getReadyBatches('LOW');
      expect(ready.map((b) => b.generatedOn), ['2026-03-29', '2026-04-05']);

      // getUnassignedReadyBatches 排除已消费 + 旧 seed 日期
      final unassigned = await dao.getUnassignedReadyBatches('LOW', '2026-03-30');
      expect(unassigned.map((b) => b.generatedOn), ['2026-04-05']);
      expect(await dao.getUnassignedReadyBatches('LOW', '2026-04-05'), isEmpty);
    });

    test('getReadyUnnotified / markReadyNotified 幂等', () async {
      final unnotified = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-08-01');
      await insertBatch(
          status: 'READY',
          difficulty: 'LOW',
          generatedOn: '2026-08-02',
          readyNotifiedAt: 1750000000000);
      await insertBatch(
          status: 'PENDING', difficulty: 'LOW', generatedOn: '2026-08-03');

      expect((await dao.getReadyUnnotified()).map((b) => b.id), [unnotified]);

      expect(await dao.markReadyNotified(unnotified, 1751000000000), 1);
      expect(await dao.getReadyUnnotified(), isEmpty);
      // 幂等：已通知不再回写
      expect(await dao.markReadyNotified(unnotified, 1752000000000), 0);
    });
  });

  group('ArticleDao', () {
    late AppDatabase db;
    late ArticleDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = ArticleDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> newBatch({String status = 'READY', String? generatedOn}) {
      return db.into(db.articleBatches).insert(ArticleBatchesCompanion.insert(
            status: status,
            difficultyLevelSnapshot: 'LOW',
            generatedOn: generatedOn ?? '2026-08-01',
            lastUpdatedAt: '2026-08-01T10:00:00+08:00',
          ));
    }

    Future<int> newArticle(int batchId, {
      String status = 'PENDING',
      int retryCount = 0,
      int accumulatedReadSeconds = 0,
      String? generationStartedAt,
      String? lastRetryAt,
      String? readCompletedAt,
    }) {
      return db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            title: Value(null),
            status: status,
            generationStartedAt: Value(generationStartedAt),
            retryCount: retryCount,
            accumulatedReadSeconds: accumulatedReadSeconds,
            readCompletedAt: Value(readCompletedAt),
            lastRetryAt: Value(lastRetryAt),
            maxRetries: 3,
          ));
    }

    test('getByBatch 按 order_index 升序 / getById / watch 发射', () async {
      final batchId = await newBatch();
      final a2 = await newArticle(batchId);
      final a1 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 0,
            contentCategory: 'GENERAL',
            status: 'PENDING',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));

      final byBatch = await dao.getByBatch(batchId);
      expect(byBatch.map((a) => a.id), [a1, a2]);

      expect((await dao.getById(a1))!.orderIndex, 0);
      expect(await dao.getById(999), isNull);

      final watched = await dao.watchByBatch(batchId).first;
      expect(watched.map((a) => a.id), [a1, a2]);
      expect((await dao.watchById(a1).first)!.id, a1);
    });

    test('claimForGeneration CAS：PENDING 可认领；SUCCESS 不可；GENERATING 可再认领', () async {
      final batchId = await newBatch();
      final pendingId = await newArticle(batchId);
      final successId = await newArticle(batchId, status: 'SUCCESS');
      final generatingId = await newArticle(batchId, status: 'GENERATING',
          generationStartedAt: '2026-08-06T10:00:00+08:00');

      // PENDING：认领成功，写 generation_started_at
      expect(await dao.claimForGeneration(pendingId, '2026-08-07T09:00:00+08:00'), 1);
      final pending = await dao.getById(pendingId);
      expect(pending!.status, 'GENERATING');
      expect(pending.generationStartedAt, '2026-08-07T09:00:00+08:00');

      // SUCCESS：认领失败（返回 0，不影响行）
      expect(await dao.claimForGeneration(successId, '2026-08-07T09:00:00+08:00'), 0);
      expect((await dao.getById(successId))!.status, 'SUCCESS');

      // GENERATING：可再认领（中断恢复），generation_started_at 保留不变
      expect(await dao.claimForGeneration(generatingId, '2026-08-07T09:00:00+08:00'), 1);
      final generating = await dao.getById(generatingId);
      expect(generating!.status, 'GENERATING');
      expect(generating.generationStartedAt, '2026-08-06T10:00:00+08:00');
    });

    test('claimForGeneration：TIMEOUT/FAILED 重试认领补 last_retry_at，保留 started_at', () async {
      final batchId = await newBatch();
      final timedOut = await newArticle(batchId, status: 'TIMEOUT',
          generationStartedAt: '2026-08-05T10:00:00+08:00');
      final failed = await newArticle(batchId, status: 'FAILED',
          generationStartedAt: null, lastRetryAt: '2026-08-05T11:00:00+08:00');

      expect(await dao.claimForGeneration(timedOut, '2026-08-07T09:00:00+08:00'), 1);
      final t = await dao.getById(timedOut);
      expect(t!.status, 'GENERATING');
      expect(t.generationStartedAt, '2026-08-05T10:00:00+08:00'); // 有值保留
      expect(t.lastRetryAt, '2026-08-07T09:00:00+08:00'); // TIMEOUT 补写

      expect(await dao.claimForGeneration(failed, '2026-08-07T09:00:00+08:00'), 1);
      final f = await dao.getById(failed);
      expect(f!.status, 'GENERATING');
      expect(f.generationStartedAt, '2026-08-07T09:00:00+08:00'); // 为空补写
      expect(f.lastRetryAt, '2026-08-07T09:00:00+08:00'); // FAILED 补写
    });

    test('markSuccess / updateStatus / updateStatusWithRetryTime / updateRetryCount', () async {
      final batchId = await newBatch();
      final id = await newArticle(batchId);

      await dao.markSuccess(id, 'Hello World', 2, '2026-08-07T09:30:00+08:00');
      final done = await dao.getById(id);
      expect(done!.status, 'SUCCESS');
      expect(done.title, 'Hello World');
      expect(done.generationCompletedAt, '2026-08-07T09:30:00+08:00');
      expect(done.retryCount, 2);

      await dao.updateStatus(id, 'TIMEOUT');
      expect((await dao.getById(id))!.status, 'TIMEOUT');

      await dao.updateStatusWithRetryTime(id, 'FAILED', '2026-08-07T10:00:00+08:00');
      final failed = await dao.getById(id);
      expect(failed!.status, 'FAILED');
      expect(failed.lastRetryAt, '2026-08-07T10:00:00+08:00');

      await dao.updateRetryCount(id, 3);
      expect((await dao.getById(id))!.retryCount, 3);
    });

    test('countByBatch / countSuccessByBatch / countPendingByBatch / countFatalByBatch', () async {
      final batchId = await newBatch();
      await newArticle(batchId, status: 'SUCCESS');
      await newArticle(batchId, status: 'SUCCESS');
      await newArticle(batchId, status: 'PENDING');
      await newArticle(batchId, status: 'TIMEOUT');
      await newArticle(batchId, status: 'FATAL');
      await newArticle(batchId, status: 'GENERATING');

      expect(await dao.countByBatch(batchId), 6);
      expect(await dao.countSuccessByBatch(batchId), 2);
      // 不含 SUCCESS/FATAL/GENERATING
      expect(await dao.countPendingByBatch(batchId), 2);
      expect(await dao.countFatalByBatch(batchId), 1);
    });

    test('resetOrphanGenerating / resetAllGenerating / resetAllTimedOutAndFailed / resetForRetry', () async {
      final batchId = await newBatch();
      final orphan = await newArticle(batchId, status: 'GENERATING',
          generationStartedAt: '2026-08-06T10:00:00+08:00', retryCount: 2);
      final other = await newArticle(batchId, status: 'GENERATING',
          generationStartedAt: '2026-08-06T11:00:00+08:00');
      final timedOut = await newArticle(batchId, status: 'TIMEOUT',
          lastRetryAt: '2026-08-06T12:00:00+08:00', retryCount: 1);
      final failed = await newArticle(batchId, status: 'FAILED');

      // 只重置本批次的 GENERATING
      await dao.resetOrphanGenerating(batchId);
      expect((await dao.getById(orphan))!.status, 'PENDING');
      expect((await dao.getById(orphan))!.retryCount, 0);
      expect((await dao.getById(orphan))!.generationStartedAt, isNull);
      expect((await dao.getById(other))!.status, 'PENDING');

      final anotherBatch = await newBatch(generatedOn: '2026-08-02');
      final keepGen = await newArticle(anotherBatch, status: 'GENERATING');
      await dao.resetAllGenerating();
      expect((await dao.getById(keepGen))!.status, 'PENDING');

      await dao.resetAllTimedOutAndFailed();
      expect((await dao.getById(timedOut))!.status, 'PENDING');
      expect((await dao.getById(timedOut))!.retryCount, 0);
      expect((await dao.getById(timedOut))!.lastRetryAt, isNull);
      expect((await dao.getById(failed))!.status, 'PENDING');

      final retry = await newArticle(batchId, status: 'FAILED', retryCount: 2);
      await dao.resetForRetry(retry);
      final r = await dao.getById(retry);
      expect(r!.status, 'PENDING');
      expect(r.retryCount, 0);
      expect(r.lastRetryAt, isNull);
    });

    test('addReadSeconds / markReadCompleted（>=120s 才标记）/ forceMarkReadCompleted', () async {
      final batchId = await newBatch();
      final a = await newArticle(batchId, accumulatedReadSeconds: 0);
      final b = await newArticle(batchId, accumulatedReadSeconds: 119);
      final c = await newArticle(batchId, accumulatedReadSeconds: 200,
          readCompletedAt: '2026-08-06T10:00:00+08:00');

      await dao.addReadSeconds(a, 50);
      expect((await dao.getById(a))!.accumulatedReadSeconds, 50);

      // 不足 120s 不标记
      await dao.markReadCompleted(b, '2026-08-07T09:00:00+08:00');
      expect((await dao.getById(b))!.readCompletedAt, isNull);
      await dao.addReadSeconds(b, 1);
      await dao.markReadCompleted(b, '2026-08-07T09:00:00+08:00');
      expect((await dao.getById(b))!.readCompletedAt, '2026-08-07T09:00:00+08:00');

      // 已标记（read_completed_at 非空）不再回写
      expect(await dao.markReadCompleted(c, '2026-08-07T09:00:00+08:00'), 0);

      // force 版本无条件标记（仍幂等）
      expect(await dao.forceMarkReadCompleted(b, '2026-08-07T10:00:00+08:00'), 0);
      expect(await dao.forceMarkReadCompleted(a, '2026-08-07T10:00:00+08:00'), 1);
      expect((await dao.getById(a))!.readCompletedAt, '2026-08-07T10:00:00+08:00');
    });

    test('insertAll 批量插入（REPLACE 语义）', () async {
      final batchId = await newBatch();
      await dao.insertAll([
        for (var i = 0; i < 3; i++)
          ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: i,
            contentCategory: 'GENERAL',
            status: 'PENDING',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ),
      ]);
      expect((await dao.getByBatch(batchId)).length, 3);
    });
  });

  group('ArticleParagraphDao', () {
    late AppDatabase db;
    late ArticleParagraphDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = ArticleParagraphDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('insertAll 后 getByArticle 按 order_index 升序；deleteByArticle 清空', () async {
      final batchId = await db.into(db.articleBatches).insert(
          ArticleBatchesCompanion.insert(
            status: 'READY',
            difficultyLevelSnapshot: 'LOW',
            generatedOn: '2026-08-01',
            lastUpdatedAt: '2026-08-01T10:00:00+08:00',
          ));
      final articleId = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            status: 'SUCCESS',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));

      await dao.insertAll([
        for (var i = 2; i >= 0; i--)
          ArticleParagraphsCompanion.insert(
            articleId: articleId,
            orderIndex: i,
            englishText: 'p$i',
            chineseTranslation: '段落$i',
          ),
      ]);

      final paragraphs = await dao.getByArticle(articleId);
      expect(paragraphs.map((p) => p.orderIndex), [0, 1, 2]);
      expect(paragraphs.first.englishText, 'p0');

      await dao.deleteByArticle(articleId);
      expect(await dao.getByArticle(articleId), isEmpty);
      // 其他文章段落不受影响
    });

    test('deleteByArticle 只删目标文章的段落', () async {
      final batchId = await db.into(db.articleBatches).insert(
          ArticleBatchesCompanion.insert(
            status: 'READY',
            difficultyLevelSnapshot: 'LOW',
            generatedOn: '2026-08-01',
            lastUpdatedAt: '2026-08-01T10:00:00+08:00',
          ));
      final a1 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            status: 'SUCCESS',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));
      final a2 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 2,
            contentCategory: 'GENERAL',
            status: 'SUCCESS',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));

      await dao.insertAll([
        ArticleParagraphsCompanion.insert(
            articleId: a1, orderIndex: 0, englishText: 'a1', chineseTranslation: '一'),
        ArticleParagraphsCompanion.insert(
            articleId: a2, orderIndex: 0, englishText: 'a2', chineseTranslation: '二'),
      ]);

      await dao.deleteByArticle(a1);
      expect(await dao.getByArticle(a1), isEmpty);
      expect((await dao.getByArticle(a2)).length, 1);
    });
  });

  group('GenerationErrorLogDao', () {
    late AppDatabase db;
    late GenerationErrorLogDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = GenerationErrorLogDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertError({
      required String entityType,
      required int entityId,
      String errorCode = 'TIMEOUT',
      String? errorHelp,
      required String createdAt,
      int? notifiedAt,
    }) {
      return dao.insert(GenerationErrorLogsCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        errorCode: errorCode,
        errorMessage: 'msg $entityId $createdAt',
        errorHelp: Value(errorHelp),
        retryCount: 1,
        createdAt: createdAt,
        notifiedAt: Value(notifiedAt),
      ));
    }

    test('insert / getByEntity 按时间倒序 / getUnnotified / markNotified 幂等', () async {
      final first = await insertError(
          entityType: 'ARTICLE',
          entityId: 1,
          createdAt: '2026-08-06T10:00:00+08:00');
      await insertError(
          entityType: 'ARTICLE',
          entityId: 1,
          createdAt: '2026-08-05T10:00:00+08:00');
      await insertError(
          entityType: 'BATCH',
          entityId: 2,
          createdAt: '2026-08-06T11:00:00+08:00');

      // 某实体全部错误历史，时间倒序
      final history = await dao.getByEntity('ARTICLE', 1);
      expect(history.map((e) => e.createdAt),
          ['2026-08-06T10:00:00+08:00', '2026-08-05T10:00:00+08:00']);

      // 未通知 + created_at >= 门槛
      final unnotified = await dao.getUnnotified('2026-08-06T00:00:00+08:00');
      expect(unnotified.length, 2);
      expect(unnotified.map((e) => e.entityId), [1, 2]);

      expect(await dao.markNotified(first, 1751000000000), 1);
      expect(await dao.markNotified(first, 1752000000000), 0); // 幂等
      final row = await (db.select(db.generationErrorLogs)
            ..where((t) => t.id.equals(first)))
          .getSingleOrNull();
      expect(row!.notifiedAt, 1751000000000);
      final unnotified2 = await dao.getUnnotified('2026-08-06T00:00:00+08:00');
      expect(unnotified2.length, 1);
    });

    test('watchArticleErrors：每篇实体只取最新一条 + 状态投影', () async {
      final batchId = await db.into(db.articleBatches).insert(
          ArticleBatchesCompanion.insert(
            status: 'READY',
            difficultyLevelSnapshot: 'LOW',
            generatedOn: '2026-08-01',
            lastUpdatedAt: '2026-08-01T10:00:00+08:00',
          ));
      final a1 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            status: 'FAILED',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));
      final a2 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 2,
            contentCategory: 'GENERAL',
            status: 'TIMEOUT',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));

      // a1 两条错误（先旧后新），a2 一条
      await insertError(
          entityType: 'ARTICLE', entityId: a1, createdAt: '2026-08-06T10:00:00+08:00');
      final a1new = await insertError(
          entityType: 'ARTICLE', entityId: a1, createdAt: '2026-08-06T11:00:00+08:00');
      await insertError(
          entityType: 'ARTICLE', entityId: a2, createdAt: '2026-08-06T12:00:00+08:00');

      final rows = await dao.watchArticleErrors().first;
      // 每篇只取最新一条，created_at 倒序（a2 的 12:00 最新排第一）
      expect(rows.length, 2);
      expect(rows[0].error.entityId, a2);
      expect(rows[0].articleStatus, 'TIMEOUT');
      expect(rows[1].error.entityId, a1);
      expect(rows[1].error.id, a1new);
      expect(rows[1].articleStatus, 'FAILED');
      expect(rows.map((r) => r.error.id), isNot(contains(a1new - 1)));
    });

    test('watchArticleErrors：实体已删除时 article_status 为 null', () async {
      final batchId = await db.into(db.articleBatches).insert(
          ArticleBatchesCompanion.insert(
            status: 'READY',
            difficultyLevelSnapshot: 'LOW',
            generatedOn: '2026-08-01',
            lastUpdatedAt: '2026-08-01T10:00:00+08:00',
          ));
      final a1 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            status: 'FAILED',
            retryCount: 0,
            accumulatedReadSeconds: 0,
            maxRetries: 3,
          ));
      await insertError(
          entityType: 'ARTICLE', entityId: a1, createdAt: '2026-08-06T10:00:00+08:00');

      await (db.delete(db.articles)..where((t) => t.id.equals(a1))).go();

      final rows = await dao.watchArticleErrors().first;
      expect(rows.length, 1);
      expect(rows[0].articleStatus, isNull);
    });
  });
}
