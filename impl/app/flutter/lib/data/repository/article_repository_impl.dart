import 'package:drift/drift.dart' hide isNull, isNotNull;

import '../../domain/model/article.dart';
import '../../domain/model/article_batch.dart';
import '../../domain/model/daily_learning_info.dart';
import '../../domain/model/generation_error.dart';
import '../../domain/repository/article_repository.dart';
import '../local/database.dart';
import '../local/daos/article_daos.dart';
import '../local/daos/settings_daos.dart';

/// 文章仓储实现（对照 Kotlin ArticleRepositoryImpl.kt，方法逐一对应）。
///
/// 关键语义：
/// - 时间注入（[nowIso] / [today]），测试可固定时钟
/// - failArticle/fatalArticle 的状态更新与错误日志写入必须在同一事务
///   （防止中间进程被杀导致日志丢失）
/// - reconcileOrphanArticles 三条重置语句在同一事务
class ArticleRepositoryImpl implements ArticleRepository {
  ArticleRepositoryImpl(
    this._db,
    this._batchDao,
    this._articleDao,
    this._paragraphDao,
    this._pipelineStatusDao,
    this._errorLogDao,
    this._dailyLearningDao,
    this._nowIso,
    this._today,
  );

  final AppDatabase _db;
  final ArticleBatchDao _batchDao;
  final ArticleDao _articleDao;
  final ArticleParagraphDao _paragraphDao;
  final GenerationPipelineStatusDao _pipelineStatusDao;
  final GenerationErrorLogDao _errorLogDao;
  final DailyLearningDao _dailyLearningDao;

  /// 当前时间（ISO 8601 偏移字符串），注入以便测试固定时钟。
  final String Function() _nowIso;

  /// 当前日期（yyyy-MM-dd），注入以便测试固定时钟。
  final String Function() _today;

  @override
  Future<ArticleBatch?> findNextReadyBatch(
          String difficulty, String? afterDate) async {
    final row = await _batchDao.findNextReadyBatch(difficulty, afterDate);
    return row?.toModel();
  }

  @override
  Future<List<ArticleBatch>> getUnassignedReadyBatches(
      String difficulty, String? minGeneratedOn) async {
    final date = minGeneratedOn ?? _today();
    final rows = await _batchDao.getUnassignedReadyBatches(difficulty, date);
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate) async {
    final dailyLearning = await _dailyLearningDao.getByLearningDate(readDate);
    if (dailyLearning == null) return null;
    final row = await _batchDao.getById(dailyLearning.refBatchId);
    return row?.toModel();
  }

  @override
  Future<List<DailyLearningInfo>> getAllDailyLearningInfos() async {
    final reads = await _dailyLearningDao.getAll();
    final infos = <DailyLearningInfo>[];
    for (final read in reads) {
      final batch = await _batchDao.getById(read.refBatchId);
      if (batch == null) continue;
      infos.add(DailyLearningInfo(
        learningDate: read.learningDate,
        dailyCountSnapshot: read.dailyCountSnapshot,
        batch: batch.toModel(),
      ));
    }
    return infos;
  }

  @override
  Future<String?> getMaxRefBatchDate() => _dailyLearningDao.getMaxRefBatchDate();

  @override
  Future<ArticleBatch?> getBatchById(int batchId) async {
    final row = await _batchDao.getById(batchId);
    return row?.toModel();
  }

  @override
  Future<bool> assignBatchForToday(
      int batchId, String refBatchDate, int dailyCount) async {
    final today = _today();
    final existing = await _dailyLearningDao.getByLearningDate(today);
    if (existing != null) return false;

    await _dailyLearningDao.insert(DailyLearningsCompanion.insert(
      learningDate: today,
      refBatchDate: refBatchDate,
      refBatchId: batchId,
      dailyCountSnapshot: dailyCount,
    ));
    return true;
  }

  @override
  Future<bool> isPipelineBlocked() async =>
      (await _pipelineStatusDao.get())?.isBlocked == true;

  @override
  Future<bool> recoverIfNewerVersion(int currentVersionCode) async {
    final status = await _pipelineStatusDao.get();
    if (status == null || !status.isBlocked) return false;
    final blockedVersion = status.blockedAppVersionCode;
    if (blockedVersion == null) return false;
    if (currentVersionCode > blockedVersion) {
      await _pipelineStatusDao.clearBlocked();
      await _articleDao.resetOrphanGenerating(0);
      return true;
    }
    return false;
  }

  @override
  Future<int> createBatch(String difficulty, {String? generatedOn}) async {
    final date = generatedOn ?? _today();
    return _batchDao.insert(ArticleBatchesCompanion.insert(
      status: 'PENDING',
      difficultyLevelSnapshot: difficulty,
      generatedOn: date,
      lastUpdatedAt: _nowIso(),
    ));
  }

  @override
  Future<void> createArticles(int batchId, List<String> categories) {
    final articles = <ArticlesCompanion>[];
    for (var i = 0; i < categories.length; i++) {
      articles.add(ArticlesCompanion.insert(
        batchId: batchId,
        orderIndex: i + 1,
        contentCategory: categories[i],
        status: 'PENDING',
        retryCount: 0,
        accumulatedReadSeconds: 0,
        maxRetries: 3,
      ));
    }
    return _articleDao.insertAll(articles);
  }

  @override
  Future<List<Article>> getArticles(int batchId) async {
    final rows = await _articleDao.getByBatch(batchId);
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<bool> claimBatch(int batchId) async =>
      (await _batchDao.claimForGeneration(batchId, _nowIso())) > 0;

  @override
  Future<bool> claimArticle(int articleId) async =>
      (await _articleDao.claimForGeneration(articleId, _nowIso())) > 0;

  @override
  Future<void> completeArticle(
      int articleId, String title, List<ArticleParagraph> paragraphs,
      {required int retryCount}) async {
    final now = _nowIso();
    await _articleDao.markSuccess(articleId, title, retryCount, now);
    await _paragraphDao.deleteByArticle(articleId);
    final entities = <ArticleParagraphsCompanion>[];
    for (var i = 0; i < paragraphs.length; i++) {
      final p = paragraphs[i];
      entities.add(ArticleParagraphsCompanion.insert(
        articleId: articleId,
        orderIndex: p.orderIndex > 0 ? p.orderIndex : i + 1,
        englishText: p.englishText,
        chineseTranslation: p.chineseTranslation,
      ));
    }
    await _paragraphDao.insertAll(entities);
  }

  @override
  Future<bool> isBatchComplete(int batchId) async {
    final total = await _articleDao.countByBatch(batchId);
    final success = await _articleDao.countSuccessByBatch(batchId);
    return total > 0 && total == success;
  }

  @override
  Future<bool> hasFatalArticle(int batchId) async =>
      (await _articleDao.countFatalByBatch(batchId)) > 0;

  @override
  Future<void> markBatchReady(int batchId) =>
      _batchDao.updateStatus(batchId, 'READY', _nowIso());

  @override
  Future<int?> markBatchBlocked(
      int batchId, String reason, int appVersionCode) async {
    final now = _nowIso();
    await _batchDao.markBlocked(batchId, reason, now);
    // 批次错误详情写入流水账，pipeline_status 只保留全局开关
    final errorLogId = await _errorLogDao.insert(GenerationErrorLogsCompanion.insert(
      entityType: 'BATCH',
      entityId: batchId,
      errorCode: 'STRUCTURAL_PIPELINE_BLOCKED',
      errorMessage: reason,
      retryCount: 0,
      createdAt: now,
    ));
    await _pipelineStatusDao.setBlocked(
        reason: reason, now: now, appVersionCode: appVersionCode);
    return errorLogId;
  }

  @override
  Future<int?> failArticle(
    int articleId,
    String status, {
    String? errorCode,
    String? errorMessage,
    String? errorHelp,
    int retryCount = 0,
  }) {
    final now = _nowIso();
    // 状态更新与错误日志写入必须在同一事务（注释见 Kotlin 原版）
    return _db.transaction(() async {
      await _articleDao.updateStatusWithRetryTime(articleId, status, now);
      if (errorCode != null || errorMessage != null) {
        return _errorLogDao.insert(GenerationErrorLogsCompanion.insert(
          entityType: 'ARTICLE',
          entityId: articleId,
          errorCode: errorCode ?? 'UNKNOWN',
          errorMessage: errorMessage ?? '未知错误',
          errorHelp: Value(errorHelp),
          retryCount: retryCount,
          createdAt: now,
        ));
      }
      return null;
    });
  }

  @override
  Future<int?> fatalArticle(
    int articleId, {
    String? errorCode,
    String? errorMessage,
    int retryCount = 0,
  }) {
    final now = _nowIso();
    return _db.transaction(() async {
      await _articleDao.updateStatusWithRetryTime(articleId, 'FATAL', now);
      if (errorCode != null || errorMessage != null) {
        return _errorLogDao.insert(GenerationErrorLogsCompanion.insert(
          entityType: 'ARTICLE',
          entityId: articleId,
          errorCode: errorCode ?? 'UNKNOWN',
          errorMessage: errorMessage ?? '未知错误',
          retryCount: retryCount,
          createdAt: now,
        ));
      }
      return null;
    });
  }

  @override
  Future<void> markErrorNotified(int errorLogId) =>
      _errorLogDao.markNotified(errorLogId, DateTime.now().millisecondsSinceEpoch);

  @override
  Future<void> markBatchReadyNotified(int batchId) =>
      _batchDao.markReadyNotified(batchId, DateTime.now().millisecondsSinceEpoch);

  @override
  Future<List<GenerationError>> getUnnotifiedErrors(String createdAfter) async {
    final rows = await _errorLogDao.getUnnotified(createdAfter);
    return rows
        .map((e) => GenerationError(
              id: e.id,
              entityId: e.entityId,
              entityType: e.entityType,
              errorCode: e.errorCode,
              errorMessage: e.errorMessage,
              errorHelp: e.errorHelp,
              retryCount: e.retryCount,
              createdAt: e.createdAt,
            ))
        .toList();
  }

  @override
  Future<List<ArticleBatch>> getReadyBatchesUnnotified() async {
    final rows = await _batchDao.getReadyUnnotified();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<void> addReadSeconds(int articleId, int deltaSeconds) =>
      _articleDao.addReadSeconds(articleId, deltaSeconds);

  @override
  Future<void> tryMarkReadCompleted(int articleId) =>
      _articleDao.markReadCompleted(articleId, _nowIso());

  @override
  Future<void> forceMarkReadCompleted(int articleId) =>
      _articleDao.forceMarkReadCompleted(articleId, _nowIso());

  @override
  Future<void> reconcileOrphanArticles() {
    // 三条重置语句在同一事务：防止部分重置导致 worker 重新调度时状态不一致
    return _db.transaction(() async {
      await _articleDao.resetAllGenerating();
      await _articleDao.resetAllTimedOutAndFailed();
      await _batchDao.resetAllGeneratingBatches();
    });
  }

  @override
  Future<List<ArticleBatch>> getGeneratingBatches() async {
    final rows = await _batchDao.getGeneratingBatches();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<List<ArticleBatch>> getPendingBatches() async {
    final rows = await _batchDao.getPendingBatches();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Stream<List<Article>> observeArticles(int batchId) =>
      _articleDao.watchByBatch(batchId).map((rows) => rows.map((r) => r.toModel()).toList());

  @override
  Future<Article?> getArticle(int articleId) async {
    final row = await _articleDao.getById(articleId);
    if (row == null) return null;
    final paragraphRows = await _paragraphDao.getByArticle(articleId);
    final model = row.toModel();
    return Article(
      id: model.id,
      batchId: model.batchId,
      orderIndex: model.orderIndex,
      contentCategory: model.contentCategory,
      title: model.title,
      status: model.status,
      generationStartedAt: model.generationStartedAt,
      generationCompletedAt: model.generationCompletedAt,
      retryCount: model.retryCount,
      accumulatedReadSeconds: model.accumulatedReadSeconds,
      readCompletedAt: model.readCompletedAt,
      lastRetryAt: model.lastRetryAt,
      maxRetries: model.maxRetries,
      nextRetryAt: model.nextRetryAt,
      paragraphs: paragraphRows
          .map((p) => ArticleParagraph(
              id: p.id,
              orderIndex: p.orderIndex,
              englishText: p.englishText,
              chineseTranslation: p.chineseTranslation))
          .toList(),
    );
  }

  @override
  Stream<List<GenerationError>> observeGenerationErrors() =>
      _errorLogDao.watchArticleErrors().map((list) => list
          .map((e) => GenerationError(
                id: e.error.id,
                entityId: e.error.entityId,
                entityType: e.error.entityType,
                errorCode: e.error.errorCode,
                errorMessage: e.error.errorMessage,
                errorHelp: e.error.errorHelp,
                retryCount: e.error.retryCount,
                createdAt: e.error.createdAt,
                status: e.articleStatus,
              ))
          .toList());

  @override
  Future<void> resetArticleForRetry(int articleId) =>
      _articleDao.resetForRetry(articleId);

  @override
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
          String difficulty, String date) async {
    final row = await _batchDao.getByDifficultyAndDate(difficulty, date);
    return row?.toModel();
  }

  @override
  Future<ArticleBatch?> getUnassignedBatchByDifficultyAndDate(
      String difficulty, String date) async {
    final row = await _batchDao.getUnassignedByDifficultyAndDate(difficulty, date);
    return row?.toModel();
  }
}

extension on ArticleBatchRow {
  ArticleBatch toModel() => ArticleBatch(
        id: id,
        status: BatchStatus.fromDbValue(status),
        difficultyLevelSnapshot: difficultyLevelSnapshot,
        generatedOn: generatedOn,
        lastUpdatedAt: lastUpdatedAt,
        blockedReason: blockedReason,
        blockedAt: blockedAt,
      );
}

extension on ArticleRow {
  Article toModel() => Article(
        id: id,
        batchId: batchId,
        orderIndex: orderIndex,
        contentCategory: contentCategory,
        title: title,
        status: ArticleStatus.fromDbValue(status),
        generationStartedAt: generationStartedAt,
        generationCompletedAt: generationCompletedAt,
        retryCount: retryCount,
        accumulatedReadSeconds: accumulatedReadSeconds,
        readCompletedAt: readCompletedAt,
        lastRetryAt: lastRetryAt,
        maxRetries: maxRetries,
        nextRetryAt: nextRetryAt,
      );
}
