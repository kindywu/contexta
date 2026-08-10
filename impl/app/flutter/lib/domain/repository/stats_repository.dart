import '../model/daily_stats.dart';

/// 统计仓储接口（对齐 Kotlin StatsRepository.kt）。
abstract interface class StatsRepository {
  /// 观察今日学习统计（无记录时发射 null）。
  Stream<DailyStats?> observeStats();

  Future<DailyStats?> getStats();

  /// 记录今天的阅读活动（+1 篇文章 + 秒数）。
  Future<void> recordReadingActivity({int secondsSpent = 0});

  /// 记录今天加入生词本一个词。
  Future<void> recordWordAdded();
}
