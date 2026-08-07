/// 每日学习统计（对齐 Kotlin DailyStats.kt）。
class DailyStats {
  final int totalArticlesRead;
  final int totalWordsAdded;
  final int totalWordsMastered;
  final int totalLearningDays;
  final int currentStreak;
  final int longestStreak;
  final String? lastActiveDate;

  const DailyStats({
    required this.totalArticlesRead,
    required this.totalWordsAdded,
    required this.totalWordsMastered,
    required this.totalLearningDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastActiveDate,
  });

  @override
  String toString() => 'DailyStats(totalArticlesRead=$totalArticlesRead, '
      'totalWordsAdded=$totalWordsAdded, '
      'totalWordsMastered=$totalWordsMastered, '
      'totalLearningDays=$totalLearningDays, currentStreak=$currentStreak, '
      'longestStreak=$longestStreak, lastActiveDate=$lastActiveDate)';
}
