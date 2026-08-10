import 'package:drift/drift.dart' hide isNull, isNotNull;

import '../../domain/model/daily_stats.dart';
import '../../domain/repository/stats_repository.dart';
import '../../domain/repository/vocabulary_repository.dart';
import '../local/database.dart';
import '../local/daos/settings_daos.dart';

/// 统计仓储实现（对照 Kotlin StatsRepositoryImpl.kt）。
///
/// 记录阅读/加词活动 → daily_learning_log 流水账 → 重算 learning_stats_summary。
/// streak 计算语义与 Kotlin 一致：今天活跃从今天往回数连续天数；
/// 昨天活跃（今天无记录）从昨天往回数；中断则归零。
class StatsRepositoryImpl implements StatsRepository {
  StatsRepositoryImpl(
    this._dailyLogDao,
    this._summaryDao,
    this._vocabularyRepository,
    this._today,
  );

  final DailyLearningLogDao _dailyLogDao;
  final LearningStatsSummaryDao _summaryDao;
  final VocabularyRepository _vocabularyRepository;

  /// 当前日期（yyyy-MM-dd），注入以便测试固定时钟。
  final String Function() _today;

  @override
  Stream<DailyStats?> observeStats() =>
      _summaryDao.observe().map((row) => row?.toModel());

  @override
  Future<DailyStats?> getStats() async {
    final row = await _summaryDao.get();
    return row?.toModel();
  }

  @override
  Future<void> recordReadingActivity({int secondsSpent = 0}) async {
    final today = _today();
    final existing = await _dailyLogDao.getByDate(today);
    if (existing == null) {
      await _dailyLogDao.upsert(DailyLearningLogsCompanion(
        logDate: Value(today),
        articlesRead: const Value(1),
        wordsAdded: const Value(0),
        secondsSpent: Value(secondsSpent),
      ));
    } else {
      await _dailyLogDao.addActivity(today, 1, secondsSpent);
    }
    await _recalculateStats(today);
  }

  @override
  Future<void> recordWordAdded() async {
    final today = _today();
    final existing = await _dailyLogDao.getByDate(today);
    if (existing == null) {
      await _dailyLogDao.upsert(DailyLearningLogsCompanion(
        logDate: Value(today),
        articlesRead: const Value(0),
        wordsAdded: const Value(1),
        secondsSpent: const Value(0),
      ));
    } else {
      await _dailyLogDao.addWordActivity(today);
    }
    await _recalculateStats(today);
  }

  Future<void> _recalculateStats(String today) async {
    final activeDates = await _dailyLogDao.getActiveDates();
    final currentStreak = _calculateStreak(activeDates, today);
    final totalDays = activeDates.length;

    final existing = await _summaryDao.get();
    final newLongestStreak =
        (existing?.longestStreak ?? 0) > currentStreak
            ? existing!.longestStreak
            : currentStreak;
    final totalWords = await _vocabularyRepository.countDistinctWords();

    var totalArticlesRead = 0;
    for (final date in activeDates) {
      final log = await _dailyLogDao.getByDate(date);
      totalArticlesRead += log?.articlesRead ?? 0;
    }

    await _summaryDao.upsert(LearningStatsSummariesCompanion(
      id: const Value(1),
      totalArticlesRead: Value(totalArticlesRead),
      totalWordsAdded: Value(totalWords),
      totalWordsMastered: const Value(0),
      totalLearningDays: Value(totalDays),
      currentStreak: Value(currentStreak),
      longestStreak: Value(newLongestStreak),
      lastActiveDate: Value(today),
    ));
  }

  /// 与 Kotlin calculateStreak 完全一致（activeDates 按日期降序）。
  int _calculateStreak(List<String> activeDates, String today) {
    if (activeDates.isEmpty) return 0;

    final lastActive = activeDates.first;
    final diff = _daysBetween(lastActive, today);

    if (diff > 1) return 0;
    if (diff == 0) {
      var streak = 1;
      var checkDate = _minusDays(today, 1);
      while (activeDates.contains(checkDate)) {
        streak++;
        checkDate = _minusDays(checkDate, 1);
      }
      return streak;
    }
    var streak = 1;
    var checkDate = _minusDays(lastActive, 1);
    while (activeDates.contains(checkDate)) {
      streak++;
      checkDate = _minusDays(checkDate, 1);
    }
    return streak;
  }

  static int _daysBetween(String from, String to) {
    final a = DateTime.parse(from);
    final b = DateTime.parse(to);
    return DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
  }

  static String _minusDays(String date, int days) {
    final d = DateTime.parse(date).subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

extension on LearningStatsSummaryRow {
  DailyStats toModel() => DailyStats(
        totalArticlesRead: totalArticlesRead,
        totalWordsAdded: totalWordsAdded,
        totalWordsMastered: totalWordsMastered,
        totalLearningDays: totalLearningDays,
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        lastActiveDate: lastActiveDate,
      );
}
