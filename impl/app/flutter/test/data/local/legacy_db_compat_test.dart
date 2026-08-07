import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/database_open.dart';

/// Task 8：drift 直接打开 Android Room 建的旧库（真机备份 fixture）。
///
/// 核心承诺验证：
/// 1. 打开本身不抛异常 —— Room 内部表（room_master_table / android_metadata）
///    被 drift 忽略；
/// 2. user_version=1 与 drift schemaVersion=1 匹配 → 不触发迁移/重建
///    （不重建证据：sqlite_sequence、rowid、Room 内部表内容打开前后不变）；
/// 3. 15 张表数据完整可读（行数 + 真实内容抽样，含 Kotlin 大写枚举原样字符串、
///    generation_error_log.notified_at 的 Unix 毫秒语义）；
/// 4. PRAGMA 级 schema 语义比对：旧库与 drift 生成的新库逐项一致
///    （列名/类型/notnull/pk/无 DEFAULT、索引名/唯一性/列序、FK on_delete）。
///
/// fixture 使用临时目录副本（不污染 test/fixtures/legacy/contexta.db；
/// 旧库是 WAL 模式，drift 打开会写 -wal/-shm 边车文件）。
const _fixtureRel = 'test/fixtures/legacy/contexta.db';

/// 拷贝 fixture 到临时目录，返回临时目录（含 contexta.db）。
Future<Directory> _copyFixtureToTemp() async {
  final tmp = await Directory.systemTemp.createTemp('contexta-legacy-');
  File(_fixtureRel).copySync('${tmp.path}/contexta.db');
  return tmp;
}

/// 用 buildAppDatabase（生产打开策略）打开旧库副本，返回 (db, 临时目录)。
Future<(AppDatabase, Directory)> _openLegacy() async {
  final tmp = await _copyFixtureToTemp();
  final db = await buildAppDatabase(overridePath: '${tmp.path}/contexta.db');
  return (db, tmp);
}

Future<void> _closeAndRemove(AppDatabase db, Directory tmp) async {
  await db.close();
  try {
    tmp.deleteSync(recursive: true);
  } catch (_) {
    // 忽略清理失败（Windows 上文件句柄释放有延迟）
  }
}

/// 打开前基线快照（直连 SQLite 只读，不经过 drift）。
Map<String, Object?> _rawBaseline(String path) {
  final raw = raw_sqlite.sqlite3.open(path, mode: raw_sqlite.OpenMode.readOnly);
  try {
    final seq = {
      for (final r in raw.select('SELECT name, seq FROM sqlite_sequence'))
        r['name'] as String: r['seq'] as int,
    };
    final settings = raw.select(
      'SELECT id, is_onboarded, difficulty_level, daily_article_count, '
      'translation_display_mode, mastery_threshold_n, auto_play_audio '
      'FROM user_settings',
    ).first;
    final vocab = raw.select(
      'SELECT id, word_id, instance_number, status, correct_review_streak, '
      'mastered_at, deleted_at, deleted_reason FROM vocabulary_entry',
    ).first;
    final roomHash = raw
        .select('SELECT identity_hash FROM room_master_table')
        .first['identity_hash'] as String;
    final locale = raw
        .select('SELECT locale FROM android_metadata')
        .first['locale'] as String;
    final version = raw.select('PRAGMA user_version').first['user_version'] as int;
    return {
      'user_version': version,
      'sqlite_sequence': seq,
      'user_settings': {
        for (final c in settings.keys) c: settings[c],
      },
      'vocabulary_entry': {
        for (final c in vocab.keys) c: vocab[c],
      },
      'room_master_table_hash': roomHash,
      'android_metadata_locale': locale,
    };
  } finally {
    raw.close();
  }
}

void main() {
  group('legacy_db_compat', () {
    // 15 张业务表（Room 内部表不在内）
    const allTables = <String>[
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
    ];

    // 打开前（sqlite3 只读基线）快照出的 sqlite_sequence：9 张有数据的
    // AUTOINCREMENT 表（config_change_log / schema_migration_log 0 行无条目）
    const expectedSqliteSequence = <String, int>{
      'article_batch': 12,
      'article': 60,
      'article_paragraph': 550,
      'daily_learning_log': 4,
      'example_sentence': 43,
      'generation_error_log': 3,
      'vocabulary_entry': 1,
      'word': 11, // word 表 10 行但 id 用到 11（4 号被删过）
      'word_sense': 30,
    };

    test('drift 打开旧 Room 库：不抛异常、user_version=1、数据行数、FK 开启、Room 内部表被忽略', () async {
      final (db, tmp) = await _openLegacy();
      try {
        // 打开本身不抛异常即通过；Room 内部表在 sqlite_master 中仍在
        final version = await db.customSelect('PRAGMA user_version').getSingle();
        expect(version.read<int>('user_version'), 1,
            reason: 'drift schemaVersion=1 与旧库 user_version=1 匹配，不触发迁移');

        // 15 张表行数与备份核验一致
        const expectedCounts = <String, int>{
          'article_batch': 12,
          'article': 60,
          'article_paragraph': 550,
          'word': 10,
          'word_sense': 30,
          'example_sentence': 43,
          'vocabulary_entry': 1,
          'daily_learning': 6,
          'user_settings': 1,
          'generation_pipeline_status': 0,
          'learning_stats_summary': 1,
          'daily_learning_log': 4,
          'config_change_log': 0,
          'schema_migration_log': 0,
          'generation_error_log': 3,
        };
        for (final e in expectedCounts.entries) {
          final row = await db.customSelect(
            'SELECT count(*) AS c FROM "${e.key}"',
          ).getSingle();
          expect(row.read<int>('c'), e.value, reason: '表 ${e.key} 行数');
        }

        // 外键开启（buildAppDatabase 的 beforeOpen 对齐 Room 默认）
        final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
        expect(fk.read<int>('foreign_keys'), 1);

        // Room 内部表被 drift 忽略（仍存在，未被删也未报错）
        final master = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('room_master_table', 'android_metadata') ORDER BY name",
        ).get();
        expect(
          [for (final r in master) r.read<String>('name')],
          ['android_metadata', 'room_master_table'],
        );
      } finally {
        await _closeAndRemove(db, tmp);
      }
    });

    test('drift 打开旧库：不重建（user_version / sqlite_sequence / rowid / Room 内部表内容不变）', () async {
      final tmp = await _copyFixtureToTemp();
      final path = '${tmp.path}/contexta.db';
      final before = _rawBaseline(path);
      expect(before['user_version'], 1);
      expect(before['sqlite_sequence'], expectedSqliteSequence,
          reason: '基线快照须与 fixture 备份核验一致（测试前提）');
      expect((before['room_master_table_hash']), '5c244e050883323130b8fff0a427c44c');
      expect(before['android_metadata_locale'], 'zh_CN');

      final db = await buildAppDatabase(overridePath: path);
      try {
        final afterVersion =
            await db.customSelect('PRAGMA user_version').getSingle();
        expect(afterVersion.read<int>('user_version'), 1,
            reason: '打开后 user_version 仍 1 —— drift 认为 schema 匹配，未触发重建');

        // sqlite_sequence 原样保留：若 drift 重建表（drop+create），
        // AUTOINCREMENT 表的 seq 会被清空重置
        final seqRows = await db.customSelect(
          'SELECT name, seq FROM sqlite_sequence',
        ).get();
        final seqAfter = {
          for (final r in seqRows) r.read<String>('name'): r.read<int>('seq'),
        };
        expect(seqAfter, expectedSqliteSequence,
            reason: 'sqlite_sequence 保留 = 未重建（AUTOINCREMENT 计数没被重置）');

        // 打开前后同一行 rowid / 内容不变（无删改、无种子重写）
        final us = await db.select(db.userSettings).getSingle();
        expect(us.id, 1);
        expect(us.isOnboarded, isTrue);
        expect(us.difficultyLevel, 'MEDIUM');
        expect(us.dailyArticleCount, 3);
        expect(us.translationDisplayMode, 'BLURRED');
        expect(us.masteryThresholdN, 1);
        expect(us.autoPlayAudio, isFalse);

        final ve = await db.select(db.vocabularyEntries).getSingle();
        expect(ve.id, 1);
        expect(ve.wordId, 6);
        expect(ve.instanceNumber, 1);
        expect(ve.status, 'NEW');
        expect(ve.correctReviewStreak, 0);
        expect(ve.masteredAt, isNull);
        expect(ve.deletedAt, isNull);
        expect(ve.deletedReason, isNull);

        // Room 内部表内容原样保留
        final hash = await db.customSelect(
          'SELECT identity_hash FROM room_master_table',
        ).getSingle();
        expect(hash.read<String>('identity_hash'), '5c244e050883323130b8fff0a427c44c');
        final locale = await db.customSelect(
          'SELECT locale FROM android_metadata',
        ).getSingle();
        expect(locale.read<String>('locale'), 'zh_CN');
      } finally {
        await _closeAndRemove(db, tmp);
      }
    });

    test('drift 打开旧库：真实内容抽样可读（含 Kotlin 枚举原样字符串、notified_at Unix 毫秒）', () async {
      final (db, tmp) = await _openLegacy();
      try {
        // article：标题 + 状态（Kotlin 枚举大写原样字符串）
        final article = (await db.select(db.articles).get())
            .firstWhere((a) => a.id == 1);
        expect(article.batchId, 1);
        expect(article.title, 'A Day at the Park');
        expect(article.status, 'SUCCESS');
        expect(article.contentCategory, isNotEmpty);

        // article_batch：status 枚举 + ready_notified_at 语义（null）
        final batch = (await db.select(db.articleBatches).get())
            .firstWhere((b) => b.id == 1);
        expect(batch.status, 'READY');
        expect(batch.difficultyLevelSnapshot, 'LOW');
        expect(batch.generatedOn, '2026-03-29');
        expect(batch.readyNotifiedAt, 1785637736683);
        expect(batch.readyNotifiedAt, greaterThan(1000000000000),
            reason: 'ready_notified_at 是 Unix 毫秒（13 位），非秒级');

        // article_paragraph：正文真实文本
        final para = (await db.select(db.articleParagraphs).get())
            .firstWhere((p) => p.id == 1);
        expect(para.articleId, 1);
        expect(para.englishText, startsWith('It is a sunny day.'));

        // word / word_sense：音标、词性、中文释义
        final word = (await db.select(db.words).get()).firstWhere((w) => w.id == 1);
        expect(word.spellingNormalized, 'premises');
        expect(word.spellingDisplay, 'premises');
        expect(word.phoneticIpa, '/ˈprɛmɪsɪz/');
        final sense = (await db.select(db.wordSenses).get())
            .firstWhere((s) => s.id == 1);
        expect(sense.partOfSpeech, 'n.');
        expect(sense.chineseMeaning, contains('房屋'));
        final sense2 = (await db.select(db.wordSenses).get())
            .firstWhere((s) => s.id == 2);
        expect(sense2.chineseMeaning, contains('前提'));

        // example_sentence：is_primary 布尔读取
        final exs = await db.select(db.exampleSentences).get();
        expect(exs, hasLength(43));
        final ex1 = exs.firstWhere((e) => e.id == 1);
        expect(ex1.wordSenseId, 1);
        expect(ex1.isPrimary, isTrue);
        expect(ex1.sentenceEn, startsWith('The company has moved to new premises'));

        // vocabulary_entry：Kotlin 枚举 NEW 原样字符串
        final ve = await db.select(db.vocabularyEntries).getSingle();
        expect(ve.status, 'NEW');

        // daily_learning：learning_date 业务主键 + 快照
        final dl = (await db.select(db.dailyLearnings).get())
            .firstWhere((d) => d.learningDate == '2026-08-02');
        expect(dl.refBatchDate, '2026-03-29');
        expect(dl.refBatchId, 3);
        expect(dl.dailyCountSnapshot, 3);

        // user_settings：枚举/布尔
        final us = await db.select(db.userSettings).getSingle();
        expect(us.difficultyLevel, 'MEDIUM');
        expect(us.translationDisplayMode, 'BLURRED');

        // learning_stats_summary：单行统计
        final ls = await db.select(db.learningStatsSummaries).getSingle();
        expect(ls.totalArticlesRead, 19);
        expect(ls.currentStreak, 4);
        expect(ls.longestStreak, 4);
        expect(ls.lastActiveDate, '2026-08-06');

        // daily_learning_log：流水账 4 条
        final logs = await db.select(db.dailyLearningLogs).get();
        expect(logs, hasLength(4));
        expect(logs.firstWhere((l) => l.id == 1).logDate, '2026-08-03');

        // generation_error_log：notified_at 是 Unix 毫秒（1e12 量级）
        final errs = await db.select(db.generationErrorLogs).get();
        expect(errs, hasLength(3));
        final err1 = errs.firstWhere((e) => e.id == 1);
        expect(err1.entityType, 'ARTICLE');
        expect(err1.entityId, 41);
        expect(err1.errorCode, 'UNEXPECTED');
        expect(err1.createdAt, '2026-08-04T07:28:51+08:00');
        expect(err1.notifiedAt, 1785799732040);
        expect(err1.notifiedAt, greaterThan(1000000000000),
            reason: 'Unix 毫秒语义（10 位=秒，13 位=毫秒；秒级 1.7e9 会小于 1e12）');

        // generation_pipeline_status：空表可读
        expect(await db.select(db.generationPipelineStatuses).get(), isEmpty);
        expect(await db.select(db.configChangeLogs).get(), isEmpty);
        expect(await db.select(db.schemaMigrationLogs).get(), isEmpty);
      } finally {
        await _closeAndRemove(db, tmp);
      }
    });

    test('schema 语义比对：旧库 15 张表 PRAGMA 与 drift 生成结构逐项一致', () async {
      final (legacy, tmp) = await _openLegacy();
      // 参照库：同一组 Table 类生成的崭新 drift 库
      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        // 表集合一致（业务表 15 张；旧库另有 room 内部表，drift 忽略）
        Future<Set<String>> tableSet(AppDatabase d) async {
          final rows = await d.customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' "
            "AND name NOT IN ('room_master_table', 'android_metadata')",
          ).get();
          return {for (final r in rows) r.read<String>('name')};
        }

        expect(await tableSet(legacy), await tableSet(fresh));
        expect(await tableSet(legacy), allTables.toSet());

        Future<List<List<Object?>>> columnsOf(AppDatabase d, String t) async {
          final rows = await d.customSelect(
            "SELECT name, type, \"notnull\", pk, dflt_value "
            "FROM pragma_table_info('$t')",
          ).get();
          return [
            for (final r in rows)
              [
                r.read<String>('name'),
                r.read<String>('type'),
                r.read<int>('notnull'),
                r.read<int>('pk'),
                r.read<String?>('dflt_value'),
              ],
          ];
        }

        Future<Map<String, int>> indexesOf(AppDatabase d, String t) async {
          final rows = await d.customSelect(
            "SELECT name, \"unique\" FROM pragma_index_list('$t') "
            "WHERE name NOT LIKE 'sqlite_%'",
          ).get();
          return {for (final r in rows) r.read<String>('name'): r.read<int>('unique')};
        }

        Future<List<String>> indexColsOf(AppDatabase d, String idx) async {
          final rows = await d.customSelect(
            "SELECT name FROM pragma_index_info('$idx')",
          ).get();
          return [for (final r in rows) r.read<String>('name')];
        }

        Future<List<Map<String, String>>> fksOf(AppDatabase d, String t) async {
          final rows = await d.customSelect(
            "SELECT \"table\" AS parent, \"from\" AS frm, \"to\" AS ref, "
            "on_delete, on_update FROM pragma_foreign_key_list('$t')",
          ).get();
          final fks = [
            for (final r in rows)
              {
                'parent': r.read<String>('parent'),
                'from': r.read<String>('frm'),
                'to': r.read<String>('ref'),
                'on_delete': r.read<String>('on_delete'),
                'on_update': r.read<String>('on_update'),
              },
          ];
          fks.sort((a, b) => '${a['parent']}|${a['from']}|${a['to']}'
              .compareTo('${b['parent']}|${b['from']}|${b['to']}'));
          return fks;
        }

        for (final t in allTables) {
          final legacyCols = await columnsOf(legacy, t);
          final freshCols = await columnsOf(fresh, t);
          expect(legacyCols, freshCols, reason: '表 $t 列（名/类型/notnull/pk/无 DEFAULT）逐项一致');

          final legacyIdx = await indexesOf(legacy, t);
          final freshIdx = await indexesOf(fresh, t);
          expect(legacyIdx, freshIdx, reason: '表 $t 索引（名 + 唯一性）一致');
          for (final name in legacyIdx.keys) {
            expect(
              await indexColsOf(legacy, name),
              await indexColsOf(fresh, name),
              reason: '索引 $name 覆盖列（顺序）一致',
            );
          }

          expect(await fksOf(legacy, t), await fksOf(fresh, t),
              reason: '表 $t 外键（父表/列/on_delete/on_update）一致');
        }
      } finally {
        await legacy.close();
        await fresh.close();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('旧库 PRAGMA 硬编码抽查（与 schema_*_tables_test 同风格断言）', () async {
      final (db, tmp) = await _openLegacy();
      try {
        // user_settings 7 列
        final usCols = await db.customSelect(
          "SELECT name, type, \"notnull\", pk FROM pragma_table_info('user_settings')",
        ).get();
        expect(usCols, hasLength(7));
        final byName = {for (final r in usCols) r.read<String>('name'): r};
        expect(byName['id']!.read<String>('type'), 'INTEGER');
        expect(byName['id']!.read<int>('pk'), 1);
        expect(byName['is_onboarded']!.read<String>('type'), 'INTEGER');
        expect(byName['difficulty_level']!.read<String>('type'), 'TEXT');
        expect(byName['auto_play_audio']!.read<int>('notnull'), 1);

        // word 表列 + 唯一索引
        final wordCols = await db.customSelect(
          "SELECT name, type, \"notnull\", pk FROM pragma_table_info('word')",
        ).get();
        final wm = {for (final r in wordCols) r.read<String>('name'): r};
        expect(wm, hasLength(4));
        expect(wm['spelling_display']!.read<String>('type'), 'TEXT');
        expect(wm['spelling_normalized']!.read<int>('notnull'), 1);
        expect(wm['phonetic_ipa']!.read<int>('notnull'), 0);
        final wordIdx = await db.customSelect(
          "SELECT name, \"unique\" FROM pragma_index_list('word')",
        ).get();
        expect(
          {for (final r in wordIdx) r.read<String>('name'): r.read<int>('unique')},
          containsPair('index_word_spelling_normalized', 1),
        );

        // example_sentence 外键 → word_sense ON DELETE CASCADE
        final fk = await db.customSelect(
          "SELECT \"table\" AS t, \"from\" AS f, \"to\" AS t2, on_delete "
          "FROM pragma_foreign_key_list('example_sentence')",
        ).getSingle();
        expect(fk.read<String>('t'), 'word_sense');
        expect(fk.read<String>('f'), 'word_sense_id');
        expect(fk.read<String>('t2'), 'id');
        expect(fk.read<String>('on_delete'), 'CASCADE');

        // daily_learning 无 AUTOINCREMENT、TEXT 主键
        final dlSql = await db.customSelect(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='daily_learning'",
        ).getSingle();
        expect(dlSql.read<String>('sql'), isNot(contains('AUTOINCREMENT')));
      } finally {
        await _closeAndRemove(db, tmp);
      }
    });
  });
}
