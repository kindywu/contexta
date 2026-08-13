import '../../domain/model/article.dart';
import '../../domain/model/article_batch.dart';
import '../../domain/model/daily_learning_info.dart';
import '../../domain/repository/article_repository.dart';
import '../local/database.dart';
import '../local/daos/article_daos.dart';
import '../local/daos/settings_daos.dart';

/// 文章仓储实现（对照 Kotlin ArticleRepositoryImpl.kt 保留方法；2026-08-13
/// 计划 B Task 6 移除本地生成管道后，只保留同步/首页/阅读链路用方法）。
class ArticleRepositoryImpl implements ArticleRepository {
  ArticleRepositoryImpl(
    this._batchDao,
    this._articleDao,
    this._paragraphDao,
    this._dailyLearningDao,
    this._nowIso,
    this._today,
  );

  final ArticleBatchDao _batchDao;
  final ArticleDao _articleDao;
  final ArticleParagraphDao _paragraphDao;
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
  Future<void> addReadSeconds(int articleId, int deltaSeconds) =>
      _articleDao.addReadSeconds(articleId, deltaSeconds);

  @override
  Future<void> tryMarkReadCompleted(int articleId) =>
      _articleDao.markReadCompleted(articleId, _nowIso());

  @override
  Future<void> forceMarkReadCompleted(int articleId) =>
      _articleDao.forceMarkReadCompleted(articleId, _nowIso());

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
      accumulatedReadSeconds: model.accumulatedReadSeconds,
      readCompletedAt: model.readCompletedAt,
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
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
          String difficulty, String date) async {
    final row = await _batchDao.getByDifficultyAndDate(difficulty, date);
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
        accumulatedReadSeconds: accumulatedReadSeconds,
        readCompletedAt: readCompletedAt,
      );
}
