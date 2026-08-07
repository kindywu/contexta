import 'package:drift/drift.dart';

import 'tables/article_tables.dart'; // 文章表组 4 张
import 'tables/settings_tables.dart';

part 'database.g.dart';

/// Contexta 主数据库（drift 侧）。
///
/// 表结构逐列对照 Android Room schema（Task 8 用真机旧库逐列比对验证）。
/// 本任务注册基础表组 7 张 + 文章表组 4 张（ArticleBatches 曾因 daily_learning
/// 外键引用被自动包含进 schema，本任务显式注册后其索引才真正生成）。
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
