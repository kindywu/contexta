import 'package:drift/drift.dart';

/// article_batch 表（对照 ArticleBatchEntity.kt）。
///
/// 本任务（Task 4）仅为满足 daily_learning.ref_batch_id 外键引用而创建类定义，
/// **不注册**到 @DriftDatabase.tables —— Task 5 注册并补剩余文章表组。
/// drift 的 references 仅要求被引用表类存在，未注册的表类合法。
///
/// Room 索引（名字与 Room 完全一致）：
/// - index_article_batch_generated_on：Index(value = ["generated_on"])
/// - index_article_batch_difficulty_level_snapshot_generated_on：
///   Index(value = ["difficulty_level_snapshot", "generated_on"], unique = true)
@DataClassName('ArticleBatchRow')
@TableIndex(
  name: 'index_article_batch_generated_on',
  columns: {#generatedOn},
)
@TableIndex(
  name: 'index_article_batch_difficulty_level_snapshot_generated_on',
  columns: {#difficultyLevelSnapshot, #generatedOn},
  unique: true,
)
class ArticleBatches extends Table {
  /// Room 表名 article_batch（类名复数，必须显式覆盖）
  @override
  String get tableName => 'article_batch';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// PENDING | GENERATING | READY | CURRENT | BLOCKED
  TextColumn get status => text()();

  TextColumn get difficultyLevelSnapshot => text()();

  /// ISO date
  TextColumn get generatedOn => text()();

  TextColumn get lastUpdatedAt => text()();

  TextColumn? get blockedReason => text().nullable()();

  TextColumn? get blockedAt => text().nullable()();

  /// 批次完成飞书告警送达时间（Unix millis）；null = 未通知，启动时补发
  IntColumn? get readyNotifiedAt => integer().nullable()();
}
