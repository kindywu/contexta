import 'package:drift/drift.dart';

import '../database.dart';

/// Task 10 DAO 文章组。
///
/// 对照 Android 原版 DAO 逐方法实现：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/dao/
///   ArticleBatchDao.kt / ArticleDao.kt / ArticleParagraphDao.kt
///
/// 2026-08-13（计划 B Task 6）：本地生成管道移除——批次/文章的 CAS 认领
/// （claimForGeneration）、状态机（updateStatus/markSuccess 等）、恢复重置
/// 系列、generation_error_log DAO 全部删除，仅保留同步/阅读链路用方法。

/// article_batch 表 DAO。
/// 对照 ArticleBatchDao.kt：getById/getByDifficultyAndDate/findNextReadyBatch/
/// insert(REPLACE)。
class ArticleBatchDao {
  ArticleBatchDao(this._db);

  final AppDatabase _db;

  Future<ArticleBatchRow?> getById(int id) =>
      (_db.select(_db.articleBatches)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ArticleBatchRow?> getByDifficultyAndDate(
          String difficulty, String date) =>
      (_db.select(_db.articleBatches)
            ..where((t) =>
                t.difficultyLevelSnapshot.equals(difficulty) &
                t.generatedOn.equals(date))
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  /// 查找下一个可用的 READY 批次（消费顺序语义，详见 Kotlin 原版注释）：
  /// - [afterDate] 为 null 时返回最早 READY（首次使用）
  /// - 否则要求 generated_on 不早于 [afterDate]（>=），且未被 daily_learning 引用。
  ///   ⚠️ 2026-08-12 修复：原实现用"严格 >"，导致断签一天（某天未打开 app）
  ///   后预生成批次（generated_on == 最后消费日）被作废，链条永久断裂、
  ///   每天现场生成。>= 使批次"等得起"（隔多少天打开都可消费），
  ///   同时 seed 旧批次（generated_on 远早于最后消费日）依然被排除。
  Future<ArticleBatchRow?> findNextReadyBatch(
      String difficulty, String? afterDate) {
    final t = _db.articleBatches;
    final consumedRefs = _db.selectOnly(_db.dailyLearnings)
      ..addColumns([_db.dailyLearnings.refBatchId]);
    final after =
        afterDate == null ? const Constant(true) : t.generatedOn.isBiggerOrEqualValue(afterDate);
    return (_db.select(t)
          ..where((row) =>
              row.status.equals('READY') &
              row.difficultyLevelSnapshot.equals(difficulty) &
              after &
              row.id.isNotInQuery(consumedRefs))
          ..orderBy([(t) => OrderingTerm.asc(t.generatedOn)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// REPLACE 语义（按主键 upsert，与 Kotlin OnConflictStrategy.REPLACE 一致）。
  Future<int> insert(ArticleBatchesCompanion batch) =>
      _db.into(_db.articleBatches).insertOnConflictUpdate(batch);
}

/// article 表 DAO。
/// 对照 ArticleDao.kt 保留方法：observe/get/insert(REPLACE)/
/// getByServerArticleId/updateSyncedArticle/addReadSeconds/markReadCompleted。
class ArticleDao {
  ArticleDao(this._db);

  final AppDatabase _db;

  Stream<List<ArticleRow>> watchByBatch(int batchId) =>
      (_db.select(_db.articles)
            ..where((t) => t.batchId.equals(batchId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .watch();

  Future<List<ArticleRow>> getByBatch(int batchId) =>
      (_db.select(_db.articles)
            ..where((t) => t.batchId.equals(batchId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  Future<ArticleRow?> getById(int id) =>
      (_db.select(_db.articles)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insert(ArticlesCompanion article) =>
      _db.into(_db.articles).insertOnConflictUpdate(article);

  /// 按服务端文章 id 查本地行（每日同步幂等键；server_article_id 唯一索引，
  /// SQLite UNIQUE 允许多 NULL——本地无服务端对应的旧文章不受影响）。
  Future<ArticleRow?> getByServerArticleId(int serverArticleId) =>
      (_db.select(_db.articles)
            ..where((t) => t.serverArticleId.equals(serverArticleId)))
          .getSingleOrNull();

  /// 同步更新服务端文章内容：title / orderIndex / contentCategory。
  /// 不触碰 status / accumulatedReadSeconds 等本地状态（阅读进度不因
  /// 服务端修订而重置）；段落由调用方先删后插（见 SyncArticlesUseCase）。
  Future<void> updateSyncedArticle(
      int articleId,
      {required String title,
      required int orderIndex,
      required String contentCategory}) =>
      (_db.update(_db.articles)..where((t) => t.id.equals(articleId)))
          .write(ArticlesCompanion(
        title: Value(title),
        orderIndex: Value(orderIndex),
        contentCategory: Value(contentCategory),
      ));

  Future<void> addReadSeconds(int articleId, int deltaSeconds) =>
      _db.customUpdate(
        'UPDATE article SET accumulated_read_seconds = accumulated_read_seconds + ? '
        'WHERE id = ?',
        variables: [Variable(deltaSeconds), Variable(articleId)],
        updates: {_db.articles},
      );

  /// 累计阅读 >= 120 秒且未标记完成时回写 read_completed_at。返回受影响行数。
  Future<int> markReadCompleted(int articleId, String now) =>
      (_db.update(_db.articles)
            ..where((t) =>
                t.id.equals(articleId) &
                t.accumulatedReadSeconds.isBiggerOrEqualValue(120) &
                t.readCompletedAt.isNull()))
          .write(ArticlesCompanion(readCompletedAt: Value(now)));

  /// 无条件标记阅读完成（仍幂等：read_completed_at 非空不再回写）。
  Future<int> forceMarkReadCompleted(int articleId, String now) =>
      (_db.update(_db.articles)
            ..where((t) => t.id.equals(articleId) & t.readCompletedAt.isNull()))
          .write(ArticlesCompanion(readCompletedAt: Value(now)));
}

/// article_paragraph 表 DAO。
/// 对照 ArticleParagraphDao.kt：getByArticle/insertAll(REPLACE)/deleteByArticle。
class ArticleParagraphDao {
  ArticleParagraphDao(this._db);

  final AppDatabase _db;

  Future<List<ArticleParagraphRow>> getByArticle(int articleId) =>
      (_db.select(_db.articleParagraphs)
            ..where((t) => t.articleId.equals(articleId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  Future<void> insertAll(List<ArticleParagraphsCompanion> paragraphs) =>
      _db.batch(
          (b) => b.insertAll(_db.articleParagraphs, paragraphs, mode: InsertMode.replace));

  Future<void> deleteByArticle(int articleId) =>
      (_db.delete(_db.articleParagraphs)..where((t) => t.articleId.equals(articleId))).go();
}
