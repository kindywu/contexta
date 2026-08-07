import 'package:drift/drift.dart';

import 'tables/article_tables.dart'; // ArticleBatches 被 daily_learning 外键引用（自动包含，Task 5 显式注册）
import 'tables/settings_tables.dart';

part 'database.g.dart';

/// Contexta 主数据库（drift 侧）。
///
/// 表结构逐列对照 Android Room schema（Task 8 用真机旧库逐列比对验证）。
/// 本任务注册基础表组 7 张；article_tables.dart 中的 ArticleBatches 类已定义
/// （daily_learning 外键引用需要）但未注册，Task 5 注册。
@DriftDatabase(
  tables: [
    UserSettings,
    ConfigChangeLogs,
    SchemaMigrationLogs,
    GenerationPipelineStatuses,
    DailyLearningLogs,
    LearningStatsSummaries,
    DailyLearnings,
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
