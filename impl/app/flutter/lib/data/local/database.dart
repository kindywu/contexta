import 'package:drift/drift.dart';

import 'tables/article_tables.dart'; // 文章表组 4 张
import 'tables/settings_tables.dart';
import 'tables/tts_cache_tables.dart';
import 'tables/word_tables.dart'; // 词库表组 4 张

part 'database.g.dart';

/// Contexta 主数据库（drift 侧）。
///
/// 表结构逐列对照 Android Room schema（Task 8 用真机旧库逐列比对验证）。
/// 已注册 17 张表：基础表组 8 张 + 文章表组 4 张 + 词库表组 4 张 + TTS 缓存 1 张
/// （DbVersion 为数据库结构版本指针表，见 tables/settings_tables.dart 注释）。
@DriftDatabase(
  tables: [
    UserSettings,
    ConfigChangeLogs,
    SchemaMigrationLogs,
    GenerationPipelineStatuses,
    DailyLearningLogs,
    LearningStatsSummaries,
    DailyLearnings,
    ArticleBatches,
    Articles,
    ArticleParagraphs,
    GenerationErrorLogs,
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
  /// 自愈（[selfHealVoiceColumns]，见本文件底部）——任何打开路径打开旧库
  /// 即自洽。生产路径（buildAppDatabase）用显式策略，其 beforeOpen 同样
  /// 调用同一 helper（database_open.dart），两处共用一份补列逻辑。
  @override
  MigrationStrategy get migration =>
      migrationStrategy ??
      MigrationStrategy(
        beforeOpen: (details) => selfHealVoiceColumns(this),
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
