import 'package:drift/drift.dart';

import 'tables/article_tables.dart'; // 文章表组 4 张
import 'tables/settings_tables.dart';
import 'tables/word_tables.dart'; // 词库表组 4 张

part 'database.g.dart';

/// Contexta 主数据库（drift 侧）。
///
/// 表结构逐列对照 Android Room schema（Task 8 用真机旧库逐列比对验证）。
/// 已注册 15 张表：基础表组 7 张 + 文章表组 4 张 + 词库表组 4 张。
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
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 数据库 schema 版本。Task 7 打开策略时对齐 Room 的 version。
  @override
  int get schemaVersion => 1;

  /// 生产构造（Task 7 提供打开策略：NativeDatabase / driftDatabase + MigrationStrategy）
  AppDatabase(super.e);

  /// 测试构造：纯内存库，不走生产 MigrationStrategy / 种子逻辑
  AppDatabase.forTesting(super.e);
}
