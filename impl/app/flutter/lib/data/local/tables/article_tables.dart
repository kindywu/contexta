import 'package:drift/drift.dart';

/// 文章表组（4 张）：article_batch / article / article_paragraph / generation_error_log。
/// 逐列对照 Android Room schema：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/entity/*.kt
///
/// Room 建表规则（drift 必须逐条一致）：
/// - 禁止 withDefault() —— Room 建表无 DEFAULT，默认值由应用代码填充
/// - 自增主键 → integer().autoIncrement()
/// - 索引名与 Room 完全一致（Room 按 表名_列名 自动命名）
///
/// 注：drift 仅对注册（@DriftDatabase.tables）的表类生成 CREATE INDEX ——
/// 未注册但被 references 自动包含的表类不生成索引，必须在注册后方可落库。
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

/// 表 article（ArticleEntity.kt）
@DataClassName('ArticleRow')
@TableIndex(
  name: 'index_article_batch_id',
  columns: {#batchId},
)
class Articles extends Table {
  /// Room 表名 article（类名复数，必须显式覆盖）
  @override
  String get tableName => 'article';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// Room: ForeignKey(ArticleBatchEntity, parent = id, child = batch_id, onDelete = CASCADE)
  IntColumn get batchId =>
      integer().references(ArticleBatches, #id, onDelete: KeyAction.cascade)();

  IntColumn get orderIndex => integer()();

  /// 生成时的类别标识（TEXT，值由生成输入决定，无枚举约束）
  TextColumn get contentCategory => text()();

  /// populated after generation succeeds
  TextColumn? get title => text().nullable()();

  /// PENDING | GENERATING | SUCCESS | TIMEOUT | FAILED | FATAL
  TextColumn get status => text()();

  TextColumn? get generationStartedAt => text().nullable()();

  TextColumn? get generationCompletedAt => text().nullable()();

  IntColumn get retryCount => integer()();

  IntColumn get accumulatedReadSeconds => integer()();

  TextColumn? get readCompletedAt => text().nullable()();

  TextColumn? get lastRetryAt => text().nullable()();

  IntColumn get maxRetries => integer()();

  TextColumn? get nextRetryAt => text().nullable()();
}

/// 表 article_paragraph（ArticleParagraphEntity.kt）
@DataClassName('ArticleParagraphRow')
@TableIndex(
  name: 'index_article_paragraph_article_id',
  columns: {#articleId},
)
@TableIndex(
  name: 'index_article_paragraph_article_id_order_index',
  columns: {#articleId, #orderIndex},
  unique: true,
)
class ArticleParagraphs extends Table {
  /// Room 表名 article_paragraph（类名复数，必须显式覆盖）
  @override
  String get tableName => 'article_paragraph';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// Room: ForeignKey(ArticleEntity, parent = id, child = article_id, onDelete = CASCADE)
  IntColumn get articleId =>
      integer().references(Articles, #id, onDelete: KeyAction.cascade)();

  IntColumn get orderIndex => integer()();

  TextColumn get englishText => text()();

  TextColumn get chineseTranslation => text()();
}

/// 表 generation_error_log（GenerationErrorLogEntity.kt）
///
/// 生成错误流水账（db:TYPE 流水账，快照语义）：记录生成管道中的错误事件，
/// 错误详情（error_code / error_message / error_help）可追溯历史，
/// 状态仍留在 article_batch / article 的 status 字段。
@DataClassName('GenerationErrorLogRow')
@TableIndex(
  name: 'index_generation_error_log_entity_type_entity_id',
  columns: {#entityType, #entityId},
)
@TableIndex(
  name: 'index_generation_error_log_created_at',
  columns: {#createdAt},
)
class GenerationErrorLogs extends Table {
  /// Room 表名 generation_error_log（类名复数，必须显式覆盖）
  @override
  String get tableName => 'generation_error_log';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// "BATCH" | "ARTICLE"
  TextColumn get entityType => text()();

  IntColumn get entityId => integer()();

  TextColumn get errorCode => text()();

  TextColumn get errorMessage => text()();

  TextColumn? get errorHelp => text().nullable()();

  /// 快照：错误发生时的重试次数
  IntColumn get retryCount => integer()();

  TextColumn get createdAt => text()();

  /// 飞书告警送达时间（Unix millis）；null = 未通知，启动时补发
  IntColumn? get notifiedAt => integer().nullable()();
}
