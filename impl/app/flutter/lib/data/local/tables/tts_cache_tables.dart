import 'package:drift/drift.dart';

import 'article_tables.dart';

/// TTS 音频缓存表（关联 article_paragraph / word）：
/// - 段落缓存：article_paragraph_id NON-NULL, word_id NULL
/// - 单词缓存（预留）：word_id NON-NULL, article_paragraph_id NULL
///
/// 中文命名规范文档 db:NAME / db:INDEX / db:TYPE（流水账）。
///
/// UNIQUE 联合 (article_paragraph_id, word_id, speed, voice_id)：每种语速 ×
/// 音色各一条缓存（voice_id 为 Task 2 加列：缓存键含音色维度，不同音色缓存
/// 互不串音；去重 / 淘汰逻辑见 TtsCacheManager）。
///
/// 淘汰策略：lastAccessedAt 升序驱逐最旧文件；由 TtsCacheManager 在
/// 每次写入后检查总大小，超限则逐条删除（DB 行 + 磁盘文件）。
@DataClassName('TtsCacheRow')
@TableIndex(
  name: 'tts_cache_last_accessed_at_index',
  columns: {#lastAccessedAt},
)
class TtsCaches extends Table {
  @override
  String get tableName => 'tts_cache';

  IntColumn get id => integer().autoIncrement()();

  /// 段落关联（paragraph → TTS 缓存）；级联删除文章段落时自动清缓存。
  IntColumn? get articleParagraphId =>
      integer().references(ArticleParagraphs, #id, onDelete: KeyAction.cascade)
          .nullable()();

  /// 单词关联（word → TTS 缓存，短期不用但预留）。
  IntColumn? get wordId => integer().nullable()();

  /// 语速：0.75 或 1.0。
  RealColumn get speed => real()();

  /// 音色（TtsVoice.dbValue）：缓存键含音色维度，不同音色缓存互不串音
  TextColumn get voiceId => text()();

  /// 缓存文件路径（相对 appSupportDir，如 tts_cache/42_1.0.wav）。
  TextColumn get filePath => text()();

  /// 文件大小（bytes）。
  IntColumn get fileSize => integer()();

  /// 缓存创建时间（Unix millis）。
  IntColumn get createdAt => integer()();

  /// 最近访问时间（读写命中即更新），用于 FIFO 淘汰。
  IntColumn get lastAccessedAt => integer()();
}
