import 'package:drift/drift.dart';

import 'tables/article_tables.dart'; // 文章表组 4 张
import 'tables/settings_tables.dart';
import 'tables/tts_cache_tables.dart';
import 'tables/word_tables.dart'; // 词库表组 4 张

part 'database.g.dart';

/// Contexta 主数据库（drift 侧）。
///
/// 表结构逐列对照 Android Room schema（Task 8 用真机旧库逐列比对验证）。
/// 已注册 16 张表：基础表组 7 张 + 文章表组 4 张 + 词库表组 4 张 + TTS 缓存 1 张。
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

  /// 生产迁移策略；为 null（forTesting）时回退默认空策略。
  final MigrationStrategy? migrationStrategy;

  @override
  MigrationStrategy get migration => migrationStrategy ?? MigrationStrategy();
}
