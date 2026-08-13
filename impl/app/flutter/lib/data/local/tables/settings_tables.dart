import 'package:drift/drift.dart';

import 'article_tables.dart';

/// 基础表组（7 张），逐列对照 Android Room schema：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/entity/*.kt
///
/// Room 建表规则（drift 必须逐条一致）：
/// - 禁止 withDefault() —— Room 建表无 DEFAULT，默认值由应用代码填充
/// - 自增主键 → integer().autoIncrement()；无自增 → integer()() + primaryKey override
/// - 索引名与 Room 完全一致（Room 按 表名_列名 自动命名）

/// 表 user_settings（UserSettingsEntity.kt：单例行 id=1，无索引无外键）
///
/// 列序说明：Room 原 7 列（id / is_onboarded / difficulty_level /
/// daily_article_count / translation_display_mode / mastery_threshold_n /
/// auto_play_audio）+ 开发期 v1 补入 tts_speed / tts_voice_id / 登录态 3 列
/// （server_phone / server_token / server_token_expires_at），共 12 列；
/// tts_voice_id（音色）紧跟 tts_speed，登录态 3 列在末尾。
/// 登录态 3 列 nullable（旧库自愈 ALTER 补列 + 未登录时无值，见
/// database.dart selfHealServerAuthColumns）。
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

  /// 朗读语速（UI 显示语速：0.8 / 1.0 / 1.2，引擎内部映射实际速率）
  RealColumn get ttsSpeed => real()();

  /// 朗读音色（TtsVoice.dbValue：BELLA | JASPER | LUNA | BRUNO | ROSIE | HUGO | KIKI | LEO）
  TextColumn get ttsVoiceId => text()();

  IntColumn get masteryThresholdN => integer()();

  BoolColumn get autoPlayAudio => boolean()();

  /// 登录态：服务端手机号（登录成功后回写；null = 未登录）。
  /// 仅存本地库，不落代码 / 日志（敏感值纪律）。
  TextColumn? get serverPhone => text().nullable()();

  /// 登录态：服务端签发的 token（null = 未登录）。
  TextColumn? get serverToken => text().nullable()();

  /// 登录态：token 过期时间（Unix millis；null = 无 token）。
  IntColumn? get serverTokenExpiresAt => integer().nullable()();

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

/// 表 db_version（数据库结构版本指针）
///
/// 单例行（id=1），记录当前库结构版本。版本模型：
/// - 库内 version = 已应用编号迁移脚本的最高目标版本（tool/migrations/NNN-*.sql），
///   无脚本时恒为 1（v1 是就地补丁期，不写编号脚本）
/// - 仓库 tool/db_version 文件 = 生产环境已发布版本（0 = 从未发布）
/// - 硬校验不变量：库内 version ≤ 文件值 + 1（库超前于发布声明即报错）
/// - 职责分离：db_version 是「当前版本指针」，推进只归 tool/migrate_db.sh 与
///   发布后的 drift onUpgrade；schema_migration_log 是「迁移历史账本」，
///   每应用一个编号脚本写一行——二者互不推导
///
/// 打开时自愈（database_open.dart beforeOpen）：表/行缺失则补建（version=1），
/// 保证旧库/asset 库打开即自洽；版本推进不归 app 管。
@DataClassName('DbVersionRow')
class DbVersion extends Table {
  /// 库表名 db_version（类名复数，必须显式覆盖）
  @override
  String get tableName => 'db_version';

  /// 单例行，恒为 1（与 UserSettings 同构：无自增主键）
  IntColumn get id => integer()();

  /// 当前库结构版本（≥ 1）
  IntColumn get version => integer()();

  /// 版本更新时间（Unix millis）
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
