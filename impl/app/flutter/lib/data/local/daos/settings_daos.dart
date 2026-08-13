import 'package:drift/drift.dart';

import '../../../core/time/iso8601.dart';
import '../database.dart';

/// Task 9 DAO 基础组。
///
/// 对照 Android 原版 DAO 逐方法实现：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/dao/*.kt
///
/// 插入默认值（无 withDefault）逐一对照 Kotlin entity 构造器默认值。
/// DAO 返回 drift Row（等价 Kotlin entity），领域模型映射在仓储层（Task 12）。

/// user_settings 表 DAO（单例行 id=1）。
/// 对照 UserSettingsDao.kt：observe/get/upsert(REPLACE)/markOnboarded。
/// Flow observe 变体留给 Task 12（Riverpod 包装）。
class UserSettingsDao {
  UserSettingsDao(this._db);

  final AppDatabase _db;

  Future<UserSettingsRow?> get() =>
      (_db.select(_db.userSettings)..where((t) => t.id.equals(1))).getSingleOrNull();

  Stream<UserSettingsRow?> observe() =>
      (_db.select(_db.userSettings)..where((t) => t.id.equals(1))).watchSingleOrNull();

  Future<void> upsert(UserSettingsCompanion settings) =>
      _db.into(_db.userSettings).insertOnConflictUpdate(settings);

  Future<void> markOnboarded() => (_db.update(_db.userSettings)
        ..where((t) => t.id.equals(1)))
      .write(const UserSettingsCompanion(isOnboarded: Value(true)));
}

/// config_change_log 表 DAO。
/// 对照 ConfigChangeLogDao.kt：insert/countToday/countThisMonth。
///
/// ⚠️ 与 Kotlin 的偏差（已记录 ledger）：Kotlin 原版把 TEXT 列与 Long 毫秒
/// 直接比较——SQLite 语义下 TEXT 恒大于 INTEGER，导致 countToday/countThisMonth
/// 恒返回 0（且全库无调用方，dead code）。本实现按方法意图修复：把毫秒边界
/// 转为 ISO 偏移日期时间字符串做窗口比较。
class ConfigChangeLogDao {
  ConfigChangeLogDao(this._db);

  final AppDatabase _db;

  Future<void> insert(ConfigChangeLogsCompanion log) =>
      _db.into(_db.configChangeLogs).insert(log);

  Future<int> countToday(String fieldName, int dayStartMillis, int dayEndMillis) =>
      countBetween(fieldName, dayStartMillis, dayEndMillis);

  Future<int> countThisMonth(
          String fieldName, int monthStartMillis, int monthEndMillis) =>
      countBetween(fieldName, monthStartMillis, monthEndMillis);

  Future<int> countBetween(String fieldName, int startMillis, int endMillis) async {
    final t = _db.configChangeLogs;
    final startIso = isoOffsetDateTime(DateTime.fromMillisecondsSinceEpoch(startMillis));
    final endIso = isoOffsetDateTime(DateTime.fromMillisecondsSinceEpoch(endMillis));
    final countExpr = t.id.count();
    final rows = await (_db.selectOnly(t)
          ..addColumns([countExpr])
          ..where(t.fieldName.equals(fieldName) &
              t.createdAt.isBiggerOrEqualValue(startIso) &
              t.createdAt.isSmallerThanValue(endIso)))
        .get();
    return rows.first.read(countExpr)!;
  }
}

/// schema_migration_log 表 DAO。
/// 对照 SchemaMigrationLogDao.kt：getLatest/insert/getCurrentVersion。
class SchemaMigrationLogDao {
  SchemaMigrationLogDao(this._db);

  final AppDatabase _db;

  Future<SchemaMigrationLogRow?> getLatest() =>
      (_db.select(_db.schemaMigrationLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> insert(SchemaMigrationLogsCompanion log) =>
      _db.into(_db.schemaMigrationLogs).insert(log);

  Future<int?> getCurrentVersion() async {
    final toVersionExpr = _db.schemaMigrationLogs.toVersion;
    final rows = await (_db.selectOnly(_db.schemaMigrationLogs)
          ..addColumns([toVersionExpr])
          ..orderBy([OrderingTerm.desc(_db.schemaMigrationLogs.id)])
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    return rows.first.read(toVersionExpr);
  }
}

/// daily_learning 表 DAO。
/// 对照 DailyLearningDao.kt：
/// getAll/getLatest/getByLearningDate/getMaxRefBatchDate/insert(ABORT)。
class DailyLearningDao {
  DailyLearningDao(this._db);

  final AppDatabase _db;

  Future<List<DailyLearningRow>> getAll() =>
      (_db.select(_db.dailyLearnings)..orderBy([(t) => OrderingTerm.desc(t.learningDate)]))
          .get();

  Future<DailyLearningRow?> getLatest() =>
      (_db.select(_db.dailyLearnings)
            ..orderBy([(t) => OrderingTerm.desc(t.learningDate)])
            ..limit(1))
          .getSingleOrNull();

  Future<DailyLearningRow?> getByLearningDate(String learningDate) =>
      (_db.select(_db.dailyLearnings)..where((t) => t.learningDate.equals(learningDate)))
          .getSingleOrNull();

  /// MAX(ref_batch_date)；null 表示尚无学习记录。
  Future<String?> getMaxRefBatchDate() async {
    final maxExpr = _db.dailyLearnings.refBatchDate.max();
    final rows = await (_db.selectOnly(_db.dailyLearnings)..addColumns([maxExpr])).get();
    if (rows.isEmpty) return null;
    return rows.first.read(maxExpr);
  }

  /// learning_date 为主键，重复插入抛 SqliteException（ABORT 语义）。
  Future<void> insert(DailyLearningsCompanion record) =>
      _db.into(_db.dailyLearnings).insert(record);
}

/// daily_learning_log 表 DAO。
/// 对照 DailyLearningLogDao.kt：
/// getByDate/upsert(REPLACE)/addActivity/addWordActivity/countActiveDays/getActiveDates。
class DailyLearningLogDao {
  DailyLearningLogDao(this._db);

  final AppDatabase _db;

  Future<DailyLearningLogRow?> getByDate(String date) =>
      (_db.select(_db.dailyLearningLogs)..where((t) => t.logDate.equals(date)))
          .getSingleOrNull();

  Future<void> upsert(DailyLearningLogsCompanion log) =>
      _db.into(_db.dailyLearningLogs).insertOnConflictUpdate(log);

  Future<void> addActivity(String date, int articlesDelta, int secondsDelta) =>
      _db.customUpdate(
        'UPDATE daily_learning_log '
        'SET articles_read = articles_read + ?, seconds_spent = seconds_spent + ? '
        'WHERE log_date = ?',
        variables: [
          Variable(articlesDelta),
          Variable(secondsDelta),
          Variable(date),
        ],
      );

  Future<void> addWordActivity(String date) => _db.customUpdate(
        'UPDATE daily_learning_log '
        'SET words_added = words_added + 1 '
        'WHERE log_date = ?',
        variables: [Variable(date)],
      );

  Future<int> countActiveDays() async {
    final t = _db.dailyLearningLogs;
    final countExpr = t.id.count();
    final rows = await (_db.selectOnly(t)
          ..addColumns([countExpr])
          ..where(t.secondsSpent.isBiggerThanValue(0) |
              t.articlesRead.isBiggerThanValue(0) |
              t.wordsAdded.isBiggerThanValue(0)))
        .get();
    return rows.first.read(countExpr)!;
  }

  Future<List<String>> getActiveDates() async {
    final t = _db.dailyLearningLogs;
    final logDateExpr = t.logDate;
    final rows = await (_db.selectOnly(t)
          ..addColumns([logDateExpr])
          ..where(t.secondsSpent.isBiggerThanValue(0) |
              t.articlesRead.isBiggerThanValue(0) |
              t.wordsAdded.isBiggerThanValue(0))
          ..orderBy([OrderingTerm.desc(t.logDate)]))
        .get();
    return rows.map((r) => r.read(logDateExpr)!).toList();
  }
}

/// learning_stats_summary 表 DAO（单例行 id=1）。
/// 对照 LearningStatsSummaryDao.kt：observe/get/upsert(REPLACE)。
class LearningStatsSummaryDao {
  LearningStatsSummaryDao(this._db);

  final AppDatabase _db;

  Future<LearningStatsSummaryRow?> get() => (_db.select(_db.learningStatsSummaries)
        ..where((t) => t.id.equals(1)))
      .getSingleOrNull();

  Stream<LearningStatsSummaryRow?> observe() =>
      (_db.select(_db.learningStatsSummaries)..where((t) => t.id.equals(1)))
          .watchSingleOrNull();

  Future<void> upsert(LearningStatsSummariesCompanion stats) =>
      _db.into(_db.learningStatsSummaries).insertOnConflictUpdate(stats);
}
