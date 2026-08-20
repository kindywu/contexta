import 'package:drift/drift.dart';

/// 文章表组（3 张）：article_batch / article / article_paragraph。
/// 逐列对照 Android Room schema：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/entity/*.kt
///
/// 2026-08-13（计划 B Task 6）：本地生成管道整体移除——article_batch 删
/// blocked_reason/blocked_at/ready_notified_at，article 删生成状态机 6 列
/// （generation_started_at/generation_completed_at/retry_count/last_retry_at/
/// max_retries/next_retry_at，status 列保留），generation_error_log 表整体删除。
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
}

/// 表 article（ArticleEntity.kt）
@DataClassName('ArticleRow')
@TableIndex(
  name: 'index_article_batch_id',
  columns: {#batchId},
)
@TableIndex(
  name: 'index_article_server_article_id',
  columns: {#serverArticleId},
  unique: true,
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

  IntColumn get accumulatedReadSeconds => integer()();

  TextColumn? get readCompletedAt => text().nullable()();

  /// 服务端文章 id（每日同步幂等键，Task 1 计划 B）。
  /// nullable + 唯一索引：SQLite UNIQUE 允许多 NULL，本地无服务端对应的
  /// 旧文章不冲突；同步时按 server_article_id 幂等 upsert。
  /// 旧库自愈补列见 database.dart selfHealArticleSyncColumn。
  IntColumn? get serverArticleId => integer().nullable()();
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
