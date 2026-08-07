import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';

/// 对照 Android Room schema（impl/app/android/.../data/local/entity/*.kt）：
/// 词库表组 4 张（word / word_sense / example_sentence / vocabulary_entry）
/// 逐列断言（列名 / 类型 / notnull / pk / 无 DEFAULT）、
/// 外键 ON DELETE CASCADE、索引名与唯一性（Room 自动命名规则逐条一致）。
///
/// Room 建表规则（drift 必须逐条一致）：
/// - Long/Int → INTEGER、String → TEXT、Boolean → INTEGER（0/1）
/// - 无 DEFAULT 子句（默认值由应用代码填充）
/// - 自增主键 → AUTOINCREMENT
void main() {
  group('schema_word_tables', () {
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

    test('word 表结构（对照 WordEntity.kt）', () async {
      final cols = await tableInfo('word');
      expect(cols.length, 4);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      // lowercase + trimmed, used for lookup, never displayed
      expectCol(cols, 'spelling_normalized', type: 'TEXT', notNull: true, pk: false);
      // canonical form displayed to user
      expectCol(cols, 'spelling_display', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'phonetic_ipa', type: 'TEXT', notNull: false, pk: false);
      expect(await tableSql('word'), contains('AUTOINCREMENT'));
    });

    test('word UNIQUE 索引 index_word_spelling_normalized', () async {
      // Room: Index(value = ["spelling_normalized"], unique = true)
      final map = await indexList('word');
      expect(map['index_word_spelling_normalized'], 1);
      expect(
        await indexInfo('index_word_spelling_normalized'),
        ['spelling_normalized'],
      );
    });

    test('word_sense 表结构（对照 WordSenseEntity.kt）', () async {
      final cols = await tableInfo('word_sense');
      expect(cols.length, 6);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'word_id', type: 'INTEGER', notNull: true, pk: false);
      // display order, context-matching sense first (0)
      expectCol(cols, 'order_index', type: 'INTEGER', notNull: true, pk: false);
      // e.g. "n.", "v."
      expectCol(cols, 'part_of_speech', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'chinese_meaning', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'english_definition', type: 'TEXT', notNull: true, pk: false);
      expect(await tableSql('word_sense'), contains('AUTOINCREMENT'));
    });

    test('word_sense 外键 → word ON DELETE CASCADE', () async {
      final rows = await db.customSelect(
        "SELECT \"table\", \"from\", \"to\", on_delete, on_update "
        "FROM pragma_foreign_key_list('word_sense')",
      ).get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'word');
      expect(fk.read<String>('from'), 'word_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
      expect(fk.read<String>('on_update'), 'NO ACTION'); // Room 默认（SQLite 报告格式）
    });

    test('word_sense 索引 index_word_sense_word_id', () async {
      // Room: Index("word_id") → 自动命名 index_word_sense_word_id
      expect((await indexList('word_sense'))['index_word_sense_word_id'], 0);
    });

    test('example_sentence 表结构（对照 ExampleSentenceEntity.kt）', () async {
      final cols = await tableInfo('example_sentence');
      expect(cols.length, 6);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'word_sense_id', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'order_index', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'sentence_en', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'sentence_zh', type: 'TEXT', notNull: true, pk: false);
      // true = context-matching example from the original article
      // Room: Boolean → INTEGER（drift boolean() 会生成 CHECK 约束，接受即可）
      expectCol(cols, 'is_primary', type: 'INTEGER', notNull: true, pk: false);
      expect(await tableSql('example_sentence'), contains('AUTOINCREMENT'));
    });

    test('example_sentence 外键 → word_sense ON DELETE CASCADE', () async {
      final rows = await db.customSelect(
        "SELECT \"table\", \"from\", \"to\", on_delete, on_update "
        "FROM pragma_foreign_key_list('example_sentence')",
      ).get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'word_sense');
      expect(fk.read<String>('from'), 'word_sense_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
      expect(fk.read<String>('on_update'), 'NO ACTION');
    });

    test('example_sentence 索引 index_example_sentence_word_sense_id', () async {
      // Room: Index("word_sense_id") → 自动命名 index_example_sentence_word_sense_id
      expect(
        (await indexList('example_sentence'))['index_example_sentence_word_sense_id'],
        0,
      );
    });

    test('vocabulary_entry 表结构（对照 VocabularyEntryEntity.kt）', () async {
      final cols = await tableInfo('vocabulary_entry');
      expect(cols.length, 8);
      expectCol(cols, 'id', type: 'INTEGER', notNull: true, pk: true);
      expectCol(cols, 'word_id', type: 'INTEGER', notNull: true, pk: false);
      // increments each time the same word is re-added
      expectCol(cols, 'instance_number', type: 'INTEGER', notNull: true, pk: false);
      // NEW | LEARNING | MASTERED
      expectCol(cols, 'status', type: 'TEXT', notNull: true, pk: false);
      expectCol(cols, 'correct_review_streak', type: 'INTEGER', notNull: true, pk: false);
      expectCol(cols, 'mastered_at', type: 'TEXT', notNull: false, pk: false);
      // soft delete
      expectCol(cols, 'deleted_at', type: 'TEXT', notNull: false, pk: false);
      // "MANUAL_REMOVAL" | "MASTERED"
      expectCol(cols, 'deleted_reason', type: 'TEXT', notNull: false, pk: false);
      expect(await tableSql('vocabulary_entry'), contains('AUTOINCREMENT'));
    });

    test('vocabulary_entry 外键 → word ON DELETE CASCADE', () async {
      final rows = await db.customSelect(
        "SELECT \"table\", \"from\", \"to\", on_delete, on_update "
        "FROM pragma_foreign_key_list('vocabulary_entry')",
      ).get();
      expect(rows, hasLength(1));
      final fk = rows.single;
      expect(fk.read<String>('table'), 'word');
      expect(fk.read<String>('from'), 'word_id');
      expect(fk.read<String>('to'), 'id');
      expect(fk.read<String>('on_delete'), 'CASCADE');
      expect(fk.read<String>('on_update'), 'NO ACTION');
    });

    test('vocabulary_entry 索引 index_vocabulary_entry_word_id', () async {
      // Room: Index("word_id") → 自动命名 index_vocabulary_entry_word_id
      expect(
        (await indexList('vocabulary_entry'))['index_vocabulary_entry_word_id'],
        0,
      );
    });

    test('注册表集合：11 张既有 + 本任务 4 张新表', () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ).get();
      final names = {for (final r in rows) r.read<String>('name')};
      // Task 6 后共 15 张。
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
        },
      );
    });
  });
}
