import 'package:drift/drift.dart';

import '../database.dart';

/// Task 10 DAO 文章组。
///
/// 对照 Android 原版 DAO 逐方法实现：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/dao/
///   ArticleBatchDao.kt / ArticleDao.kt / ArticleParagraphDao.kt / GenerationErrorLogDao.kt
///
/// CAS 认领（claimForGeneration）语义与 Kotlin 完全一致：
/// - 批次认领只认 PENDING/GENERATING（GENERATING 是中断恢复关键）
/// - 文章认领认 PENDING/TIMEOUT/FAILED/GENERATING，CASE 分支保持
///   generation_started_at 语义（PENDING 或空补写 now，重试保留原值）

/// generation_error_log × article 状态投影（对照 Kotlin GenerationErrorWithStatus，
/// 用于首页判断 canRetry）。
class GenerationErrorWithStatus {
  const GenerationErrorWithStatus({required this.error, this.articleStatus});

  final GenerationErrorLogRow error;

  /// LEFT JOIN article 投影的当前状态；实体已删除时为 null。
  final String? articleStatus;
}

/// article_batch 表 DAO。
/// 对照 ArticleBatchDao.kt：getById/getByDifficultyAndDate/findNextReadyBatch/
/// getReadyBatches/getUnassignedReadyBatches/insert(REPLACE)/claimForGeneration/
/// updateStatus/markBlocked/getGeneratingBatches/resetAllGeneratingBatches/
/// getReadyUnnotified/markReadyNotified。
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
  /// - 否则要求 generated_on 严格晚于 [afterDate]，且未被 daily_learning 引用
  Future<ArticleBatchRow?> findNextReadyBatch(
      String difficulty, String? afterDate) {
    final t = _db.articleBatches;
    final consumedRefs = _db.selectOnly(_db.dailyLearnings)
      ..addColumns([_db.dailyLearnings.refBatchId]);
    final after =
        afterDate == null ? const Constant(true) : t.generatedOn.isBiggerThanValue(afterDate);
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

  /// 指定难度的所有 READY 批次（含可能已被 daily_learning 引用的）。
  Future<List<ArticleBatchRow>> getReadyBatches(String difficulty) =>
      (_db.select(_db.articleBatches)
            ..where((t) =>
                t.status.equals('READY') &
                t.difficultyLevelSnapshot.equals(difficulty))
            ..orderBy([(t) => OrderingTerm.asc(t.generatedOn)]))
          .get();

  /// 指定难度下未被 daily_learning 引用、且 generated_on 严格晚于
  /// [minGeneratedOn] 的 READY 批次（忽略旧 seed 数据）。
  Future<List<ArticleBatchRow>> getUnassignedReadyBatches(
      String difficulty, String minGeneratedOn) {
    final t = _db.articleBatches;
    final consumedRefs = _db.selectOnly(_db.dailyLearnings)
      ..addColumns([_db.dailyLearnings.refBatchId]);
    return (_db.select(t)
          ..where((row) =>
              row.status.equals('READY') &
              row.difficultyLevelSnapshot.equals(difficulty) &
              row.generatedOn.isBiggerThanValue(minGeneratedOn) &
              row.id.isNotInQuery(consumedRefs))
          ..orderBy([(t) => OrderingTerm.asc(t.generatedOn)]))
        .get();
  }

  /// REPLACE 语义（按主键 upsert，与 Kotlin OnConflictStrategy.REPLACE 一致）。
  Future<int> insert(ArticleBatchesCompanion batch) =>
      _db.into(_db.articleBatches).insertOnConflictUpdate(batch);

  /// CAS：仅当批次处于 PENDING/GENERATING 时认领为 GENERATING。
  /// 返回受影响行数（0 = 认领失败）。认 GENERATING 是中断恢复的关键。
  Future<int> claimForGeneration(int batchId, String now) =>
      (_db.update(_db.articleBatches)
            ..where((t) =>
                t.id.equals(batchId) & t.status.isIn(['PENDING', 'GENERATING'])))
          .write(ArticleBatchesCompanion(
        status: const Value('GENERATING'),
        lastUpdatedAt: Value(now),
      ));

  Future<void> updateStatus(int batchId, String newStatus, String now) =>
      (_db.update(_db.articleBatches)..where((t) => t.id.equals(batchId)))
          .write(ArticleBatchesCompanion(
        status: Value(newStatus),
        lastUpdatedAt: Value(now),
      ));

  Future<void> markBlocked(int batchId, String? reason, String now) =>
      (_db.update(_db.articleBatches)..where((t) => t.id.equals(batchId)))
          .write(ArticleBatchesCompanion(
        status: const Value('BLOCKED'),
        blockedReason: Value(reason),
        blockedAt: Value(now),
        lastUpdatedAt: Value(now),
      ));

  /// 所有 GENERATING 批次（启动恢复：重新调度卡死的批次）。
  Future<List<ArticleBatchRow>> getGeneratingBatches() =>
      (_db.select(_db.articleBatches)..where((t) => t.status.equals('GENERATING')))
          .get();

  /// 所有 GENERATING 批次重置为 PENDING（启动恢复）。
  Future<void> resetAllGeneratingBatches() =>
      (_db.update(_db.articleBatches)..where((t) => t.status.equals('GENERATING')))
          .write(const ArticleBatchesCompanion(status: Value('PENDING')));

  /// READY 但完成通知未送达的批次（启动时补发飞书通知）。
  Future<List<ArticleBatchRow>> getReadyUnnotified() =>
      (_db.select(_db.articleBatches)
            ..where((t) => t.status.equals('READY') & t.readyNotifiedAt.isNull()))
          .get();

  /// 回写批次完成通知送达时间（幂等：只写一次）。返回受影响行数。
  Future<int> markReadyNotified(int batchId, int at) =>
      (_db.update(_db.articleBatches)
            ..where((t) => t.id.equals(batchId) & t.readyNotifiedAt.isNull()))
          .write(ArticleBatchesCompanion(readyNotifiedAt: Value(at)));
}

/// article 表 DAO。
/// 对照 ArticleDao.kt 全方法：observe/get/insert(REPLACE)/insertAll/
/// claimForGeneration(CASE)/updateStatus/updateStatusWithRetryTime/markSuccess/
/// updateRetryCount/各种 count/reset 系列/addReadSeconds/markReadCompleted。
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

  Stream<ArticleRow?> watchById(int id) =>
      (_db.select(_db.articles)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insert(ArticlesCompanion article) =>
      _db.into(_db.articles).insertOnConflictUpdate(article);

  /// REPLACE 语义批量插入（Kotlin insertAll 忽略返回值，故返回 void）。
  Future<void> insertAll(List<ArticlesCompanion> articles) =>
      _db.batch((b) => b.insertAll(_db.articles, articles, mode: InsertMode.replace));

  /// CAS 认领单篇文章。生成 started_at 语义（对照 Kotlin 注释）：
  /// - PENDING 认领 → 写 now（新一轮生成开始）
  /// - TIMEOUT/FAILED 重试认领 → started_at 为空补写 now，有值保留
  /// - last_retry_at 仅在 TIMEOUT/FAILED 重试时补写 now
  /// 认 GENERATING 是「中断/未完成重试」的关键。
  Future<int> claimForGeneration(int articleId, String now) => _db.customUpdate(
        "UPDATE article SET status = 'GENERATING', "
        "generation_started_at = CASE "
        "WHEN status = 'PENDING' OR generation_started_at IS NULL THEN ? "
        "ELSE generation_started_at END, "
        "last_retry_at = CASE WHEN status IN ('TIMEOUT', 'FAILED') THEN ? "
        "ELSE last_retry_at END "
        "WHERE id = ? AND status IN ('PENDING', 'TIMEOUT', 'FAILED', 'GENERATING')",
        variables: [Variable(now), Variable(now), Variable(articleId)],
        updates: {_db.articles},
      );

  Future<void> updateStatus(int articleId, String status) =>
      (_db.update(_db.articles)..where((t) => t.id.equals(articleId)))
          .write(ArticlesCompanion(status: Value(status)));

  /// 更新状态并记录重试时间（错误详情由 generation_error_log 记录）。
  Future<void> updateStatusWithRetryTime(
          int articleId, String status, String now) =>
      (_db.update(_db.articles)..where((t) => t.id.equals(articleId)))
          .write(ArticlesCompanion(status: Value(status), lastRetryAt: Value(now)));

  Future<void> markSuccess(int articleId, String title, int retryCount, String now) =>
      (_db.update(_db.articles)..where((t) => t.id.equals(articleId)))
          .write(ArticlesCompanion(
        title: Value(title),
        status: const Value('SUCCESS'),
        generationCompletedAt: Value(now),
        retryCount: Value(retryCount),
      ));

  Future<void> updateRetryCount(int articleId, int count) =>
      (_db.update(_db.articles)..where((t) => t.id.equals(articleId)))
          .write(ArticlesCompanion(retryCount: Value(count)));

  Future<int> countSuccessByBatch(int batchId) =>
      _countWhere((t) => t.batchId.equals(batchId) & t.status.equals('SUCCESS'));

  /// 待处理：状态不在 SUCCESS/FATAL/GENERATING 的文章数。
  Future<int> countPendingByBatch(int batchId) => _countWhere(
      (t) => t.batchId.equals(batchId) & t.status.isNotIn(['SUCCESS', 'FATAL', 'GENERATING']));

  Future<int> countFatalByBatch(int batchId) =>
      _countWhere((t) => t.batchId.equals(batchId) & t.status.equals('FATAL'));

  Future<int> countByBatch(int batchId) =>
      _countWhere((t) => t.batchId.equals(batchId));

  Future<int> _countWhere(
      Expression<bool> Function($ArticlesTable t) predicate) async {
    final t = _db.articles;
    final countExpr = t.id.count();
    final rows = await (_db.selectOnly(t)
          ..addColumns([countExpr])
          ..where(predicate(t)))
        .get();
    return rows.first.read(countExpr)!;
  }

  /// 批次内卡在 GENERATING 的文章重置回 PENDING（清重试计数与生成开始时间）。
  /// batchId = 0 时重置所有批次（与 Kotlin 原版一致：WHERE batch_id = 0 匹配
  /// 不到任何行，实际效果等同全表重置——Kotlin 的 recovery 语义依赖此行为）。
  Future<void> resetOrphanGenerating(int batchId) =>
      (_db.update(_db.articles)
            ..where((t) => t.status.equals('GENERATING') &
                (batchId == 0 ? const Constant(true) : t.batchId.equals(batchId))))
          .write(const ArticlesCompanion(
        status: Value('PENDING'),
        retryCount: Value(0),
        generationStartedAt: Value(null),
      ));

  /// 所有卡在 GENERATING 的文章重置回 PENDING（应用启动时调用）。
  Future<void> resetAllGenerating() =>
      (_db.update(_db.articles)..where((t) => t.status.equals('GENERATING')))
          .write(const ArticlesCompanion(
        status: Value('PENDING'),
        retryCount: Value(0),
        generationStartedAt: Value(null),
      ));

  /// 所有 TIMEOUT/FAILED 文章重置回 PENDING（应用启动时调用）。
  Future<void> resetAllTimedOutAndFailed() =>
      (_db.update(_db.articles)..where((t) => t.status.isIn(['TIMEOUT', 'FAILED'])))
          .write(const ArticlesCompanion(
        status: Value('PENDING'),
        retryCount: Value(0),
        lastRetryAt: Value(null),
      ));

  Future<void> resetForRetry(int articleId) =>
      (_db.update(_db.articles)..where((t) => t.id.equals(articleId)))
          .write(const ArticlesCompanion(
        status: Value('PENDING'),
        retryCount: Value(0),
        lastRetryAt: Value(null),
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

/// generation_error_log 表 DAO。
/// 对照 GenerationErrorLogDao.kt：insert(REPLACE)/observeArticleErrors/
/// getByEntity/getUnnotified/markNotified。
class GenerationErrorLogDao {
  GenerationErrorLogDao(this._db);

  final AppDatabase _db;

  Future<int> insert(GenerationErrorLogsCompanion error) =>
      _db.into(_db.generationErrorLogs).insertOnConflictUpdate(error);

  /// 观察所有 ARTICLE 错误，每篇实体只取最新一条（按创建时间倒序）。
  /// LEFT JOIN article 投影当前状态；实体已删除时 status 为 null。
  /// 与原版 SQL 逐字一致（含 MAX(id) 相关子查询），用 customSelect 保真。
  Stream<List<GenerationErrorWithStatus>> watchArticleErrors() {
    final query = _db.customSelect(
      "SELECT e.*, a.status AS article_status "
      "FROM generation_error_log e "
      "LEFT JOIN article a ON a.id = e.entity_id "
      "WHERE e.entity_type = 'ARTICLE' "
      "AND e.id = (SELECT MAX(e2.id) FROM generation_error_log e2 "
      "WHERE e2.entity_type = 'ARTICLE' AND e2.entity_id = e.entity_id) "
      "ORDER BY e.created_at DESC",
      readsFrom: {_db.generationErrorLogs, _db.articles},
    );
    return query.map((row) {
      final error = _db.generationErrorLogs.map(row.data);
      return GenerationErrorWithStatus(
        error: error,
        articleStatus: row.readNullable<String>('article_status'),
      );
    }).watch();
  }

  /// 某实体的全部错误历史（按时间倒序）。
  Future<List<GenerationErrorLogRow>> getByEntity(
          String entityType, int entityId) =>
      (_db.select(_db.generationErrorLogs)
            ..where((t) =>
                t.entityType.equals(entityType) & t.entityId.equals(entityId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// [createdAfter] 之后创建且告警未送达的错误（启动时补发飞书告警）。
  Future<List<GenerationErrorLogRow>> getUnnotified(String createdAfter) =>
      (_db.select(_db.generationErrorLogs)
            ..where((t) =>
                t.notifiedAt.isNull() &
                t.createdAt.isBiggerOrEqualValue(createdAfter))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 回写告警送达时间（幂等：只写一次）。返回受影响行数。
  Future<int> markNotified(int id, int at) =>
      (_db.update(_db.generationErrorLogs)
            ..where((t) => t.id.equals(id) & t.notifiedAt.isNull()))
          .write(GenerationErrorLogsCompanion(notifiedAt: Value(at)));
}
