import '../model/article.dart';
import '../model/article_batch.dart';
import '../model/daily_learning_info.dart';
import '../model/generation_error.dart';

/// 文章仓储接口（对齐 Kotlin ArticleRepository.kt，方法逐一对应）。
abstract interface class ArticleRepository {
  /// 观察批次内文章列表（drift watch，首页/阅读页列表流）。
  Stream<List<Article>> observeArticles(int batchId);

  /// 单篇文章（含段落）。
  Future<Article?> getArticle(int articleId);

  /// 生成管道是否全局阻塞。
  Future<bool> isPipelineBlocked();

  /// 应用版本升级后解锁被阻塞的管道。返回是否已恢复。
  Future<bool> recoverIfNewerVersion(int currentVersionCode);

  /// 按难度与生成日期查找批次（防止同一天对同难度重复创建）。
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
      String difficulty, String date);

  /// 查找下一个可用的 READY 批次：
  /// - [afterDate] 为 null 返回最早的 READY（首次使用）
  /// - 否则返回 generated_on 严格晚于 [afterDate] 且未被 daily_learning 引用的批次
  Future<ArticleBatch?> findNextReadyBatch(String difficulty, String? afterDate);

  /// 未被 daily_learning 引用的 READY 批次（generated_on 升序）。
  /// [minGeneratedOn] 为 null 时取今天。
  Future<List<ArticleBatch>> getUnassignedReadyBatches(
      String difficulty, String? minGeneratedOn);

  /// 指定阅读日期已分配的批次。
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate);

  /// 所有阅读记录（含关联批次），按日期降序。
  Future<List<DailyLearningInfo>> getAllDailyLearningInfos();

  /// 所有阅读记录中的最大 refBatchDate；无记录时为 null。
  Future<String?> getMaxRefBatchDate();

  /// 按 ID 获取批次。
  Future<ArticleBatch?> getBatchById(int batchId);

  /// 将批次分配给今天（插入 daily_learning）。
  /// 返回是否成功插入（今天已有记录返回 false）。
  Future<bool> assignBatchForToday(
      int batchId, String refBatchDate, int dailyCount);

  /// 创建新批次（PENDING），返回批次 id。
  Future<int> createBatch(String difficulty, {String? generatedOn});

  /// 为批次创建文章行（PENDING）。
  Future<void> createArticles(int batchId, List<String> categories);

  /// 批次内文章列表（suspend，供 worker 使用）。
  Future<List<Article>> getArticles(int batchId);

  /// CAS 认领批次（仅 PENDING/GENERATING），返回是否认领成功。
  Future<bool> claimBatch(int batchId);

  /// CAS 认领文章（仅 PENDING/TIMEOUT/FAILED/GENERATING），返回是否成功。
  Future<bool> claimArticle(int articleId);

  /// 标记文章成功并写入段落。
  Future<void> completeArticle(
      int articleId, String title, List<ArticleParagraph> paragraphs,
      {required int retryCount});

  /// 批次内文章是否全部 SUCCESS。
  Future<bool> isBatchComplete(int batchId);

  /// 批次内是否有 FATAL 文章。
  Future<bool> hasFatalArticle(int batchId);

  /// 标记批次 READY。
  Future<void> markBatchReady(int batchId);

  /// 标记批次 BLOCKED 并写入错误流水账 + 全局开关。
  /// 返回 BATCH 错误流水账 id（无错误详情时为 null）。
  Future<int?> markBatchBlocked(
      int batchId, String reason, int appVersionCode);

  /// 标记文章 FAILED/TIMEOUT，错误详情写入流水账。
  /// 返回错误流水账 id（无错误详情时为 null）。
  Future<int?> failArticle(
    int articleId,
    String status, {
    String? errorCode,
    String? errorMessage,
    String? errorHelp,
    int retryCount = 0,
  });

  /// 标记文章 FATAL，错误详情写入流水账。返回流水账 id。
  Future<int?> fatalArticle(
    int articleId, {
    String? errorCode,
    String? errorMessage,
    int retryCount = 0,
  });

  /// 回写错误告警送达时间（幂等）。
  Future<void> markErrorNotified(int errorLogId);

  /// 回写批次完成通知送达时间（幂等）。
  Future<void> markBatchReadyNotified(int batchId);

  /// [createdAfter]（ISO 时间字符串）之后创建且告警未送达的错误（启动补发）。
  Future<List<GenerationError>> getUnnotifiedErrors(String createdAfter);

  /// 已 READY 但完成通知未送达的批次（启动补发）。
  Future<List<ArticleBatch>> getReadyBatchesUnnotified();

  /// 累加阅读秒数。
  Future<void> addReadSeconds(int articleId, int deltaSeconds);

  /// 累计 >= 120 秒且未标记时回写 read_completed_at。
  Future<void> tryMarkReadCompleted(int articleId);

  /// 无条件标记阅读完成（幂等）。
  Future<void> forceMarkReadCompleted(int articleId);

  /// 启动恢复：重置孤儿 GENERATING/TIMEOUT/FAILED 文章与 GENERATING 批次。
  Future<void> reconcileOrphanArticles();

  /// 所有 GENERATING 批次（启动恢复用）。
  Future<List<ArticleBatch>> getGeneratingBatches();

  /// 观察每篇文章的最新生成错误（joined article status）。
  Stream<List<GenerationError>> observeGenerationErrors();

  /// 手动重试：清除错误状态并重置文章为 PENDING。
  Future<void> resetArticleForRetry(int articleId);
}
