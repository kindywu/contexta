import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';

/// 对照 Android Room schema（impl/app/android/.../data/local/entity/*.kt）：
/// 7 张基础表逐列断言（列名 / 类型 / notnull / pk / 无 DEFAULT），
/// daily_learning 额外断言外键（→ article_batch ON DELETE CASCADE）与索引名。
///
/// Room 建表规则（drift 必须逐条一致）：
/// - Long/Int → INTEGER、Boolean → INTEGER（drift sqlite boolean 映射）、String → TEXT
/// - 无 DEFAULT 子句（默认值由应用代码填充）
/// - 自增主键 → AUTOINCREMENT；无自增 → 裸 INTEGER PRIMARY KEY
void main() {
  group('schema_base_tables', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<Map<String, Map<String, Object?>>> tableInfo(String table) async {
      final rows = await db.customSelect(
        "SELECT name, type, \"notnull\", pk, dflt_value "
        "FROM pragma_table_info('$table')",
      ).get();
      return {
        for (final r in rows)
          r.read<String>('name'): {
            'type': r.read<String>('type'),
            'notnull': r.read<int>('notnull'),
            'pk': r.read<int>('pk'),
            'dflt': r.read<String?>('dflt_value'),
          },
      };
    }

    void expectCol(
      Map<String, Map<String, Object?>> cols,
      String name, {
      required String type,
      required bool notNull,
      required bool pk,
    }) {
      expect(cols[name], isNotNull, reason: '列 $name 应存在');
      expect(cols[name]!['type'], type, reason: '列 $name 类型');
      expect(
        cols[name]!['notnull'],
        notNull ? 1 : 0,
        reason: '列 $name notnull',
      );
      expect(cols[name]!['pk'], pk ? 1 : 0, reason: '列 $name pk');
      expect(cols[name]!['dflt'], isNull, reason: '列 $name 不应有 DEFAULT');
    }

    Future<String> tableSql(String table) async {
      final rows = await db.customSelect(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='$table'",
      ).get();
      expect(rows, hasLength(1), reason: '表 $table 应存在');
      return rows.single.read<String>('sql');
    }

    test('user_settings 表结构（对照 UserSettingsEntity.kt）', () async {
      final cols = await tableInfo('user_settings');
      expect(cols.length, 7);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'is_onboarded', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'difficulty_level', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'daily_article_count', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'translation_display_mode', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'mastery_threshold_n', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'auto_play_audio', type: 'INTEGER', notNull: true, pk: false);
      // Room: @PrimaryKey val id: Int（无 autoGenerate）→ 无 AUTOINCREMENT
      expect(await tableSql('user_settings'), isNot(contains('AUTOINCREMENT')));
    });

    test('config_change_log 表结构（对照 ConfigChangeLogEntity.kt）', () async {
      final cols = await tableInfo('config_change_log');
      expect(cols.length, 5);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'field_name', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'old_value', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'new_value', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'created_at', type: 'TEXT', notNull: true, pk: false);
      // Room: @PrimaryKey(autoGenerate = true) → AUTOINCREMENT
      expect(await tableSql('config_change_log'), contains('AUTOINCREMENT'));
    });

    test('schema_migration_log 表结构（对照 SchemaMigrationLogEntity.kt）', () async {
      final cols = await tableInfo('schema_migration_log');
      expect(cols.length, 5);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'from_version', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'to_version', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'description', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'created_at', type: 'TEXT', notNull: true, pk: false);
      expect(await tableSql('schema_migration_log'), contains('AUTOINCREMENT'));
    });

    test('generation_pipeline_status 表结构（对照 GenerationPipelineStatusEntity.kt）', () async {
      final cols = await tableInfo('generation_pipeline_status');
      expect(cols.length, 5);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'is_blocked', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'blocked_reason', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'blocked_at', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'blocked_app_version_code', type: 'INTEGER', notNull: false, pk: false);
      // Room: @PrimaryKey val id: Int（无 autoGenerate）
      expect(await tableSql('generation_pipeline_status'), isNot(contains('AUTOINCREMENT')));
    });

    test('daily_learning_log 表结构（对照 DailyLearningLogEntity.kt）', () async {
      final cols = await tableInfo('daily_learning_log');
      expect(cols.length, 5);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'log_date', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'articles_read', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'words_added', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'seconds_spent', type: 'INTEGER', notNull: true, pk: false);
      expect(await tableSql('daily_learning_log'), contains('AUTOINCREMENT'));
    });

    test('learning_stats_summary 表结构（对照 LearningStatsSummaryEntity.kt）', () async {
      final cols = await tableInfo('learning_stats_summary');
      expect(cols.length, 8);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'total_articles_read', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'total_words_added', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'total_words_mastered', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'total_learning_days', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'current_streak', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'longest_streak', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'last_active_date', type: 'TEXT', notNull: false, pk: false);
      // Room: @PrimaryKey val id: Int（无 autoGenerate）
      expect(await tableSql('learning_stats_summary'), isNot(contains('AUTOINCREMENT')));
    });

    test('daily_learning 表结构（对照 DailyLearningEntity.kt）', () async {
      final cols = await tableInfo('daily_learning');
      expect(cols.length, 4);
      expectCol(cols, 'learning_date', type: 'TEXT', notNull: true, pk: true);
      expectCol(cols, 'ref_batch_date', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'ref_batch_id', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'daily_count_snapshot', type: 'INTEGER', notNull: true, pk: false);
    });

    test('daily_learning 外键 → article_batch ON DELETE CASCADE', () async {
      final rows = await db.customSelect(
        "SELECT \"table\", \"from\", \"to\", on_delete, on_update "
        "FROM pragma_foreign_key_list('daily_learning')",
      ).get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'article_batch');
      expect(fk.read<String>('from'), 'ref_batch_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
      expect(fk.read<String>('on_update'), 'NO ACTION'); // Room 默认（SQLite 报告格式）
    });

    test('daily_learning 索引 index_daily_learning_ref_batch_id', () async {
      final rows = await db.customSelect(
        "SELECT name, \"unique\" FROM pragma_index_list('daily_learning')",
      ).get();
      final byName = {for (final r in rows) r.read<String>('name'): r};
      final idx = byName['index_daily_learning_ref_batch_id'];
      expect(idx, isNotNull, reason: '索引名须与 Room 一致（Room 自动命名）');
      expect(idx!.read<int>('unique'), 0);
    });

    test('注册 7 张基础表 + article_batch（FK 引用自动包含，其余表留待后续任务）', () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ).get();
      final names = {for (final r in rows) r.read<String>('name')};
      // drift 2.34 代码生成：daily_learning 的 references 使 ArticleBatches
      // 自动包含进 schema（drift_dev 警告 "will be included in this database"）。
      // 该表类未在 @DriftDatabase.tables 中注册，Task 5 显式注册并补剩余表。
      expect(
        names,
        {
          'user_settings',
          'config_change_log',
          'schema_migration_log',
          'generation_pipeline_status',
          'daily_learning_log',
          'learning_stats_summary',
          'daily_learning',
          'article_batch',
        },
      );
    });
  });
}
