import '../model/article.dart';
import '../model/article_batch.dart';
import '../model/daily_learning_info.dart';

/// 文章仓储接口（对齐 Kotlin ArticleRepository.kt 保留方法；2026-08-13
/// 计划 B Task 6 移除本地生成管道后，删去全部生成/告警方法——CAS 认领、
/// 完成/失败标记、pipeline 阻塞、错误流水账、孤儿修复、启动恢复等）。
abstract interface class ArticleRepository {
  /// 观察批次内文章列表（drift watch，首页/阅读页列表流）。
  Stream<List<Article>> observeArticles(int batchId);

  /// 单篇文章（含段落）。
  Future<Article?> getArticle(int articleId);

  /// 按难度与生成日期查找批次（防止同一天对同难度重复创建）。
  Future<ArticleBatch?> getBatchByDifficultyAndDate(
      String difficulty, String date);

  /// 查找下一个可用的 READY 批次：
  /// - [afterDate] 为 null 返回最早的 READY（首次使用）
  /// - 否则返回 generated_on 严格晚于 [afterDate] 且未被 daily_learning 引用的批次
  Future<ArticleBatch?> findNextReadyBatch(String difficulty, String? afterDate);

  /// 指定阅读日期已分配的批次。
  Future<ArticleBatch?> getAssignedBatchForDate(String readDate);

  /// 所有阅读记录（含关联批次），按日期降序。
  Future<List<DailyLearningInfo>> getAllDailyLearningInfos();

  /// 将批次分配给今天（插入 daily_learning）。
  /// 返回是否成功插入（今天已有记录返回 false）。
  Future<bool> assignBatchForToday(
      int batchId, String refBatchDate, int dailyCount);

  /// 累加阅读秒数。
  Future<void> addReadSeconds(int articleId, int deltaSeconds);

  /// 累计 >= 120 秒且未标记时回写 read_completed_at。
  Future<void> tryMarkReadCompleted(int articleId);

  /// 无条件标记阅读完成（幂等）。
  Future<void> forceMarkReadCompleted(int articleId);
}
