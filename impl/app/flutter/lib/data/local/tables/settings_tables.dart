import 'package:drift/drift.dart';

import 'article_tables.dart';

/// 基础表组（7 张），逐列对照 Android Room schema：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/entity/*.kt
///
/// Room 建表规则（drift 必须逐条一致）：
/// - 禁止 withDefault() —— Room 建表无 DEFAULT，默认值由应用代码填充
/// - 自增主键 → integer().autoIncrement()；无自增 → integer()() + primaryKey override
/// - 索引名与 Room 完全一致（Room 按 表名_列名 自动命名）

/// 表 user_settings（UserSettingsEntity.kt：单例行 id=1，7 列全 NOT NULL，无索引无外键）
@DataClassName('UserSettingsRow')
class UserSettings extends Table {
  /// Room 表名 user_settings（类名复数，显式覆盖保持一致）
  @override
  String get tableName => 'user_settings';

  /// Room: @PrimaryKey val id: Int（无 autoGenerate）
  IntColumn get id => integer()();

  BoolColumn get isOnboarded => boolean()();

  /// LOW | MEDIUM | HIGH（枚举存 TEXT 枚举名）
  TextColumn get difficultyLevel => text()();

  IntColumn get dailyArticleCount => integer()();

  /// FULL | BLURRED | HIDDEN
  TextColumn get translationDisplayMode => text()();

  IntColumn get masteryThresholdN => integer()();

  BoolColumn get autoPlayAudio => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 表 config_change_log（ConfigChangeLogEntity.kt）
@DataClassName('ConfigChangeLogRow')
class ConfigChangeLogs extends Table {
  /// Room 表名 config_change_log（类名复数，必须显式覆盖）
  @override
  String get tableName => 'config_change_log';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// currently only "daily_article_count"
  TextColumn get fieldName => text()();

  TextColumn get oldValue => text()();

  TextColumn get newValue => text()();

  TextColumn get createdAt => text()();
}

/// 表 schema_migration_log（SchemaMigrationLogEntity.kt）
@DataClassName('SchemaMigrationLogRow')
class SchemaMigrationLogs extends Table {
  /// Room 表名 schema_migration_log（类名复数，必须显式覆盖）
  @override
  String get tableName => 'schema_migration_log';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  IntColumn get fromVersion => integer()();

  IntColumn get toVersion => integer()();

  TextColumn get description => text()();

  TextColumn get createdAt => text()();
}

/// 表 generation_pipeline_status（GenerationPipelineStatusEntity.kt：单例行 id=1）
@DataClassName('GenerationPipelineStatusRow')
class GenerationPipelineStatuses extends Table {
  /// Room 表名 generation_pipeline_status（类名复数，必须显式覆盖）
  @override
  String get tableName => 'generation_pipeline_status';

  /// Room: @PrimaryKey val id: Int（无 autoGenerate）
  IntColumn get id => integer()();

  BoolColumn get isBlocked => boolean()();

  TextColumn? get blockedReason => text().nullable()();

  TextColumn? get blockedAt => text().nullable()();

  IntColumn? get blockedAppVersionCode => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 表 daily_learning_log（DailyLearningLogEntity.kt）
@DataClassName('DailyLearningLogRow')
class DailyLearningLogs extends Table {
  /// Room 表名 daily_learning_log（类名复数，必须显式覆盖）
  @override
  String get tableName => 'daily_learning_log';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// ISO date "2026-07-29"
  TextColumn get logDate => text()();

  IntColumn get articlesRead => integer()();

  IntColumn get wordsAdded => integer()();

  IntColumn get secondsSpent => integer()();
}

/// 表 learning_stats_summary（LearningStatsSummaryEntity.kt：单例行 id=1）
@DataClassName('LearningStatsSummaryRow')
class LearningStatsSummaries extends Table {
  /// Room 表名 learning_stats_summary（类名复数，必须显式覆盖）
  @override
  String get tableName => 'learning_stats_summary';

  /// Room: @PrimaryKey val id: Int（无 autoGenerate）
  IntColumn get id => integer()();

  IntColumn get totalArticlesRead => integer()();

  IntColumn get totalWordsAdded => integer()();

  IntColumn get totalWordsMastered => integer()();

  IntColumn get totalLearningDays => integer()();

  IntColumn get currentStreak => integer()();

  IntColumn get longestStreak => integer()();

  /// ISO date
  TextColumn? get lastActiveDate => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 表 daily_learning（DailyLearningEntity.kt）
///
/// learning_date 是 PRIMARY KEY，确保每天最多一条记录。
/// ref_batch_id 外键 → article_batch.id，ON DELETE CASCADE。
@DataClassName('DailyLearningRow')
@TableIndex(
  name: 'index_daily_learning_ref_batch_id',
  columns: {#refBatchId},
)
class DailyLearnings extends Table {
  /// Room 表名 daily_learning（类名复数，必须显式覆盖）
  @override
  String get tableName => 'daily_learning';

  /// Room: @PrimaryKey @ColumnInfo(name = "learning_date")（TEXT 主键，无自增）
  TextColumn get learningDate => text()();

  /// article_batch.generated_on
  TextColumn get refBatchDate => text()();

  /// Room: ForeignKey(ArticleBatchEntity, parent = id, child = ref_batch_id, onDelete = CASCADE)
  IntColumn get refBatchId =>
      integer().references(ArticleBatches, #id, onDelete: KeyAction.cascade)();

  /// 用户设置快照
  IntColumn get dailyCountSnapshot => integer()();

  @override
  Set<Column> get primaryKey => {learningDate};
}
