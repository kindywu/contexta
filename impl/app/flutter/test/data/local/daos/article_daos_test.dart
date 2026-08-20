import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';

/// Task 10 DAO 文章组测试（2026-08-13 计划 B Task 6：本地生成管道移除，
/// CAS 认领 / 状态机 / 恢复重置 / generation_error_log DAO 测试删除，
/// 仅保留同步/阅读链路用方法）。
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
    }) {
      return db.into(db.articleBatches).insert(ArticleBatchesCompanion.insert(
            status: status,
            difficultyLevelSnapshot: difficulty,
            generatedOn: generatedOn,
            lastUpdatedAt: lastUpdatedAt ?? '2026-08-01T10:00:00+08:00',
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

    test('findNextReadyBatch：afterDate null 返回最早 READY；不早于已消费日期（>=，批次等得起）', () async {
      final earliest = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-03-29');
      final later = await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-04-05');
      await insertBatch(
          status: 'READY', difficulty: 'LOW', generatedOn: '2026-04-10');

      // 首次使用：返回最早 READY 批次
      expect((await dao.findNextReadyBatch('LOW', null))!.generatedOn, '2026-03-29');
      // 2026-08-12 修复（>=）：== afterDate 的未消费批次也可选（断签自愈：
      // 08-07 生成的批次在 08-09 打开时 maxRefDate=08-07 仍可消费），
      // asc 排序下返回最早的那个
      expect((await dao.findNextReadyBatch('LOW', '2026-03-29'))!.id, earliest);
      // 04-05 >= 03-29 且未消费，若 03-29 已被消费则返回 04-05
      await db.into(db.dailyLearnings).insert(DailyLearningsCompanion.insert(
            learningDate: '2026-08-01',
            refBatchDate: '2026-03-29',
            refBatchId: earliest,
            dailyCountSnapshot: 3,
          ));
      expect((await dao.findNextReadyBatch('LOW', '2026-03-29'))!.id, later);
      expect((await dao.findNextReadyBatch('LOW', '2026-04-10'))!.generatedOn,
          '2026-04-10');
      // 早于 afterDate 的批次不回头分配
      expect(await dao.findNextReadyBatch('LOW', '2026-04-15'), isNull);
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
      String status = 'SUCCESS',
      int accumulatedReadSeconds = 0,
      String? readCompletedAt,
    }) {
      return db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            title: Value(null),
            status: status,
            accumulatedReadSeconds: accumulatedReadSeconds,
            readCompletedAt: Value(readCompletedAt),
          ));
    }

    test('getByBatch 按 order_index 升序 / getById / watch 发射', () async {
      final batchId = await newBatch();
      final a2 = await newArticle(batchId);
      final a1 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 0,
            contentCategory: 'GENERAL',
            status: 'SUCCESS',
            accumulatedReadSeconds: 0,
          ));

      final byBatch = await dao.getByBatch(batchId);
      expect(byBatch.map((a) => a.id), [a1, a2]);

      expect((await dao.getById(a1))!.orderIndex, 0);
      expect(await dao.getById(999), isNull);

      final watched = await dao.watchByBatch(batchId).first;
      expect(watched.map((a) => a.id), [a1, a2]);
    });

    test('getByServerArticleId / updateSyncedArticle（同步链路）', () async {
      final batchId = await newBatch();
      final id = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 1,
            contentCategory: 'GENERAL',
            title: Value('旧标题'),
            status: 'SUCCESS',
            accumulatedReadSeconds: 120,
            serverArticleId: Value(7),
          ));

      expect((await dao.getByServerArticleId(7))!.id, id);
      expect(await dao.getByServerArticleId(999), isNull);

      await dao.updateSyncedArticle(
        id,
        title: '新标题',
        orderIndex: 2,
        contentCategory: 'NEWS',
      );
      final row = await dao.getById(id);
      expect(row!.title, '新标题');
      expect(row.orderIndex, 2);
      expect(row.contentCategory, 'NEWS');
      // 本地阅读状态不因同步重置
      expect(row.accumulatedReadSeconds, 120);
      expect(row.status, 'SUCCESS');
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
            accumulatedReadSeconds: 0,
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
            accumulatedReadSeconds: 0,
          ));
      final a2 = await db.into(db.articles).insert(ArticlesCompanion.insert(
            batchId: batchId,
            orderIndex: 2,
            contentCategory: 'GENERAL',
            status: 'SUCCESS',
            accumulatedReadSeconds: 0,
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
}
