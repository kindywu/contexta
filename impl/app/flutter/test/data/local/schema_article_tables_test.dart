import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';

/// 对照 Android Room schema（impl/app/android/.../data/local/entity/*.kt）：
/// 文章表组 4 张（article_batch / article / article_paragraph / generation_error_log）
/// 逐列断言（列名 / 类型 / notnull / pk / 无 DEFAULT）、
/// 外键 ON DELETE CASCADE、索引名与唯一性（Room 自动命名规则逐条一致）。
///
/// Room 建表规则（drift 必须逐条一致）：
/// - Long/Int → INTEGER、String → TEXT
/// - 无 DEFAULT 子句（默认值由应用代码填充）
/// - 自增主键 → AUTOINCREMENT
void main() {
  group('schema_article_tables', () {
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

    /// pragma_index_list：索引名 -> unique（0/1）
    Future<Map<String, int>> indexList(String table) async {
      final rows = await db.customSelect(
        "SELECT name, \"unique\" FROM pragma_index_list('$table')",
      ).get();
      return {for (final r in rows) r.read<String>('name'): r.read<int>('unique')};
    }

    /// pragma_index_info：索引覆盖的列（按 seqno 排序）
    Future<List<String>> indexInfo(String index) async {
      final rows = await db.customSelect(
        "SELECT name FROM pragma_index_info('$index')",
      ).get();
      return [for (final r in rows) r.read<String>('name')];
    }

    test('article_batch 表结构（对照 ArticleBatchEntity.kt）', () async {
      final cols = await tableInfo('article_batch');
      expect(cols.length, 8);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'status', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'difficulty_level_snapshot', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'generated_on', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'last_updated_at', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'blocked_reason', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'blocked_at', type: 'TEXT', notNull: false, pk: false);
      // Room: ready_notified_at: Long?（Unix millis）
      expectCol(cols, 'ready_notified_at', type: 'INTEGER', notNull: false, pk: false);
      expect(await tableSql('article_batch'), contains('AUTOINCREMENT'));
    });

    test('article_batch 索引（名字与 Room 自动命名一致）', () async {
      final map = await indexList('article_batch');
      // Room: Index(value = ["generated_on"])
      expect(map['index_article_batch_generated_on'], 0);
      // Room: Index(value = ["difficulty_level_snapshot", "generated_on"], unique = true)
      expect(map['index_article_batch_difficulty_level_snapshot_generated_on'], 1);
      expect(
        await indexInfo('index_article_batch_difficulty_level_snapshot_generated_on'),
        ['difficulty_level_snapshot', 'generated_on'],
      );
    });

    test('article 表结构（对照 ArticleEntity.kt）', () async {
      final cols = await tableInfo('article');
      expect(cols.length, 14);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'batch_id', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'order_index', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'content_category', type: 'TEXT', notNull: true, pk: false);
      // populated after generation succeeds
      expectCol(cols, 'title', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'status', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'generation_started_at', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'generation_completed_at', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'retry_count', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'accumulated_read_seconds', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'read_completed_at', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'last_retry_at', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'max_retries', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'next_retry_at', type: 'TEXT', notNull: false, pk: false);
      expect(await tableSql('article'), contains('AUTOINCREMENT'));
    });

    test('article 外键 → article_batch ON DELETE CASCADE', () async {
      final rows = await db.customSelect(
        "SELECT \"table\", \"from\", \"to\", on_delete, on_update "
        "FROM pragma_foreign_key_list('article')",
      ).get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'article_batch');
      expect(fk.read<String>('from'), 'batch_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
      expect(fk.read<String>('on_update'), 'NO ACTION'); // Room 默认（SQLite 报告格式）
    });

    test('article 索引 index_article_batch_id', () async {
      // Room: Index("batch_id") → 自动命名 index_article_batch_id
      expect((await indexList('article'))['index_article_batch_id'], 0);
    });

    test('article_paragraph 表结构（对照 ArticleParagraphEntity.kt）', () async {
      final cols = await tableInfo('article_paragraph');
      expect(cols.length, 5);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'article_id', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'order_index', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'english_text', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'chinese_translation', type: 'TEXT', notNull: true, pk: false);
      expect(await tableSql('article_paragraph'), contains('AUTOINCREMENT'));
    });

    test('article_paragraph 外键 → article ON DELETE CASCADE', () async {
      final rows = await db.customSelect(
        "SELECT \"table\", \"from\", \"to\", on_delete, on_update "
        "FROM pragma_foreign_key_list('article_paragraph')",
      ).get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'article');
      expect(fk.read<String>('from'), 'article_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
      expect(fk.read<String>('on_update'), 'NO ACTION');
    });

    test('article_paragraph 索引（名字与 Room 自动命名一致）', () async {
      final map = await indexList('article_paragraph');
      // Room: Index("article_id")
      expect(map['index_article_paragraph_article_id'], 0);
      // Room: Index(value = ["article_id", "order_index"], unique = true)
      expect(map['index_article_paragraph_article_id_order_index'], 1);
      expect(
        await indexInfo('index_article_paragraph_article_id_order_index'),
        ['article_id', 'order_index'],
      );
    });

    test('generation_error_log 表结构（对照 GenerationErrorLogEntity.kt）', () async {
      final cols = await tableInfo('generation_error_log');
      expect(cols.length, 9);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'entity_type', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'entity_id', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'error_code', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'error_message', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'error_help', type: 'TEXT', notNull: false, pk: false);
      expectCol(cols, 'retry_count', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'created_at', type: 'TEXT', notNull: true, pk: false);
      // Room: notified_at: Long?（Unix millis）
      expectCol(cols, 'notified_at', type: 'INTEGER', notNull: false, pk: false);
      expect(await tableSql('generation_error_log'), contains('AUTOINCREMENT'));
    });

    test('generation_error_log 索引（名字与 Room 自动命名一致）', () async {
      final map = await indexList('generation_error_log');
      // Room: Index(value = ["entity_type", "entity_id"])
      expect(map['index_generation_error_log_entity_type_entity_id'], 0);
      // Room: Index(value = ["created_at"])
      expect(map['index_generation_error_log_created_at'], 0);
    });

    test('注册表集合：全部 17 张（16 张业务表 + db_version 版本指针表）', () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ).get();
      final names = {for (final r in rows) r.read<String>('name')};
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
          'article',
          'article_paragraph',
          'generation_error_log',
          'word',
          'word_sense',
          'example_sentence',
          'vocabulary_entry',
          'tts_cache',
          'db_version',
        },
      );
    });
  });
}
