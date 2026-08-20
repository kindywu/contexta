import 'package:drift/drift.dart';

import 'tables/article_tables.dart'; // 文章表组 3 张
import 'tables/settings_tables.dart';
import 'tables/tts_cache_tables.dart';
import 'tables/word_tables.dart'; // 词库表组 4 张

part 'database.g.dart';

/// Contexta 主数据库（drift 侧）。
///
/// 表结构逐列对照 Android Room schema（Task 8 用真机旧库逐列比对验证）。
/// 已注册 15 张表：基础表组 7 张 + 文章表组 3 张 + 词库表组 4 张 + TTS 缓存 1 张
/// （DbVersion 为数据库结构版本指针表，见 tables/settings_tables.dart 注释）。
/// 2026-08-13（计划 B Task 6）：本地生成管道移除——generation_pipeline_status /
/// generation_error_log 两表注册删除，文章表组从 4 张减到 3 张。
@DriftDatabase(
  tables: [
    UserSettings,
    ConfigChangeLogs,
    SchemaMigrationLogs,
    DailyLearningLogs,
    LearningStatsSummaries,
    DailyLearnings,
    ArticleBatches,
    Articles,
    ArticleParagraphs,
    Words,
    WordSenses,
    ExampleSentences,
    VocabularyEntries,
    TtsCaches,
    DbVersion,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 数据库 schema 版本。Task 7 打开策略时对齐 Room 的 version。
  @override
  int get schemaVersion => 1;

  /// 生产构造（由 buildAppDatabase 使用）：可挂载 MigrationStrategy
  /// （FK 开启 + 全新库种子写入）。
  ///
  /// 注意：drift 2.x 的迁移策略通过 [migration] getter 提供（生成代码的
  /// 构造函数不接受该参数），故这里把策略存为字段，getter 为空时回退到
  /// 默认空策略（即 forTesting 的行为：不走迁移回调、不种种子）。
  /// 构造名为公开的 `open`（而非 `_open`）：Dart 的私有成员按 library
  /// 隔离，database_open.dart 是独立库，无法调用私有构造。
  AppDatabase.open(super.e, {this.migrationStrategy});

  /// 测试构造：纯内存库，不走生产 MigrationStrategy / 种子逻辑
  AppDatabase.forTesting(super.e) : migrationStrategy = null;

  /// 生产迁移策略；为 null（forTesting）时回退到默认策略。
  final MigrationStrategy? migrationStrategy;

  /// 默认迁移策略：无显式策略（forTesting 等）也执行 beforeOpen 幂等补列
  /// 自愈（[selfHealVoiceColumns] 等，见本文件底部）——任何打开路径打开
  /// 旧库即自洽。生产路径（buildAppDatabase）用显式策略，其 beforeOpen
  /// 同样调用同一组 helper（database_open.dart），两处共用一份补列逻辑。
  @override
  MigrationStrategy get migration =>
      migrationStrategy ??
      MigrationStrategy(
        beforeOpen: (details) async {
          await selfHealVoiceColumns(this);
          await selfHealServerAuthColumns(this);
          await selfHealArticleSyncColumn(this);
        },
      );
}

/// 开发期 v1 结构变更自愈：旧库 / asset 旧库缺失新列时幂等补列，保证任何库
/// 打开即自洽（与 db_version 自愈同模式）。SQLite ALTER TABLE ADD COLUMN 无
/// IF NOT EXISTS，先查 pragma_table_info。
///
/// 供两处调用：默认迁移策略（forTesting 等无显式策略的打开路径）与生产
/// buildAppDatabase 的 beforeOpen（database_open.dart）——所有打开路径统一
/// 走同一补列逻辑。仅用于开发期 v1 结构变更；发布后结构变更走编号迁移脚本
/// （tool/migrations/NNN-*.sql）。
Future<void> selfHealVoiceColumns(AppDatabase db) async {
  await _ensureColumn(
    db, 'user_settings', 'tts_voice_id',
    "tts_voice_id TEXT NOT NULL DEFAULT 'BELLA'",
  );
  await _ensureColumn(
    db, 'tts_cache', 'voice_id',
    "voice_id TEXT NOT NULL DEFAULT 'BELLA'",
  );
}

/// 开发期 v1 结构变更自愈：user_settings 登录态 3 列（server_phone /
/// server_token / server_token_expires_at）。幂等语义同 [selfHealVoiceColumns]
/// （先查 pragma_table_info 再 ALTER——SQLite 无 ADD COLUMN IF NOT EXISTS，
/// 已存在列跳过，重复打开安全）。供默认迁移策略与生产 beforeOpen 共用
/// （database_open.dart）。仅用于开发期 v1 结构变更；发布后走编号迁移脚本。
Future<void> selfHealServerAuthColumns(AppDatabase db) async {
  await _ensureColumn(db, 'user_settings', 'server_phone', 'server_phone TEXT');
  await _ensureColumn(db, 'user_settings', 'server_token', 'server_token TEXT');
  await _ensureColumn(
    db,
    'user_settings',
    'server_token_expires_at',
    'server_token_expires_at INTEGER',
  );
}

/// 开发期 v1 结构变更自愈：article.server_article_id（同步幂等键）+ 唯一索引。
/// 列幂等同 _ensureColumn；索引用 CREATE UNIQUE INDEX IF NOT EXISTS 天然幂等。
/// 唯一索引允许多 NULL（SQLite 语义）——本地旧文章不受约束影响。
Future<void> selfHealArticleSyncColumn(AppDatabase db) async {
  await _ensureColumn(
    db, 'article', 'server_article_id', 'server_article_id INTEGER',
  );
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS `index_article_server_article_id` '
    'ON `article` (`server_article_id`)',
  );
}

/// 幂等补列：列不存在时执行 ADD COLUMN（SQLite 无 ADD COLUMN IF NOT EXISTS）。
/// 仅用于开发期 v1 结构变更；发布后结构变更走编号迁移脚本（tool/migrations/NNN-*.sql）。
Future<void> _ensureColumn(
  AppDatabase db,
  String table,
  String column,
  String ddl,
) async {
  final rows = await db.customSelect(
    "SELECT 1 FROM pragma_table_info('$table') WHERE name = '$column'",
  ).get();
  if (rows.isEmpty) {
    await db.customStatement('ALTER TABLE $table ADD COLUMN $ddl');
  }
}
