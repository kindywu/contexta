import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

import 'package:contexta/data/local/database.dart';

/// beforeOpen 幂等补列：旧结构库（缺新列）打开后列被补上、旧行取默认值。
///
/// 决策记录（brief Step 6 注记 + API 偏差）：
/// 1. drift 2.34.3 实测行为：旧结构库 user_version=0 → 打开时走 onCreate →
///    `createAll` 的 `CREATE TABLE IF NOT EXISTS` 跳过已存在的旧表（不报错、
///    也不补列）；默认 onUpgrade 只在 user_version>0 且 ≠ schemaVersion 时
///    触发（否则抛异常）。故补列逻辑挂进默认迁移策略的 beforeOpen
///    （database.dart 的 `migration` getter 回退路径），与生产
///    buildAppDatabase 的 beforeOpen 共用同一 `selfHealVoiceColumns`——
///    任何打开路径（含 forTesting）打开旧库即自愈。本测试验证该行为。
/// 2. brief 原测试代码对 `NativeDatabase.memory()` 调 `customStatement` 不可
///    编译（NativeDatabase 是 QueryExecutor，无该方法）；改为用 sqlite3
///    原生连接预建旧结构表，再经 `NativeDatabase.opened` 包装交给 drift。
void main() {
  group('database_patch_columns', () {
    test('旧结构库打开自愈：user_settings/tts_cache 补列且旧行默认 BELLA', () async {
      final raw = raw_sqlite.sqlite3.openInMemory();
      raw.execute(
        'CREATE TABLE user_settings ('
        'id INTEGER NOT NULL PRIMARY KEY, is_onboarded INTEGER NOT NULL, '
        'difficulty_level TEXT NOT NULL, daily_article_count INTEGER NOT NULL, '
        'translation_display_mode TEXT NOT NULL, tts_speed REAL NOT NULL, '
        'mastery_threshold_n INTEGER NOT NULL, auto_play_audio INTEGER NOT NULL)');
      raw.execute(
        'INSERT INTO user_settings (id, is_onboarded, difficulty_level, '
        'daily_article_count, translation_display_mode, tts_speed, '
        'mastery_threshold_n, auto_play_audio) VALUES '
        "(1, 1, 'MEDIUM', 3, 'FULL', 1.0, 1, 0)");
      raw.execute(
        'CREATE TABLE tts_cache ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, '
        'article_paragraph_id INTEGER, word_id INTEGER, '
        'speed REAL NOT NULL, file_path TEXT NOT NULL, '
        'file_size INTEGER NOT NULL, created_at INTEGER NOT NULL, '
        'last_accessed_at INTEGER NOT NULL)');

      // closeUnderlyingOnClose 默认 true：db.close() 会顺带关闭 raw 连接
      final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
      try {
        final cols = await db.customSelect(
          "SELECT name, dflt_value FROM pragma_table_info('user_settings')",
        ).get();
        final ttsVoice = cols.firstWhere(
          (r) => r.read<String>('name') == 'tts_voice_id');
        expect(ttsVoice.read<String?>('dflt_value'), "'BELLA'");

        final cacheCols = await db.customSelect(
          "SELECT name FROM pragma_table_info('tts_cache')",
        ).get();
        expect(
          cacheCols.map((r) => r.read<String>('name')),
          contains('voice_id'));

        final row = await db.customSelect(
          'SELECT tts_voice_id FROM user_settings WHERE id = 1',
        ).getSingle();
        expect(row.read<String>('tts_voice_id'), 'BELLA');
      } finally {
        await db.close();
      }
    });

    test('新结构库打开：补列 helper 不重复执行（幂等）', () async {
      final mem = NativeDatabase.memory();
      final db = AppDatabase.forTesting(mem);
      try {
        final cols = await db.customSelect(
          "SELECT name FROM pragma_table_info('user_settings')",
        ).get();
        expect(
          cols.map((r) => r.read<String>('name')),
          contains('tts_voice_id'));
      } finally {
        await db.close();
      }
    });
  });
}
