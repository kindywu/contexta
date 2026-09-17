import 'package:drift/drift.dart';

import 'article_tables.dart';

/// TTS 音频缓存表（关联 article_paragraph / word）：
/// - 句子缓存：article_paragraph_id NON-NULL, word_id NULL（sentence_index
///   标识段内第几句；朗读单元 = 句子）
/// - 单词缓存（预留）：word_id NON-NULL, article_paragraph_id NULL
///
/// 中文命名规范文档 db:NAME / db:INDEX / db:TYPE（流水账）。
///
/// 去重键 (article_paragraph_id, sentence_index, speed, voice_id)：每句 ×
/// 每种语速 × 音色各一条缓存（不同音色缓存互不串音；去重 / 淘汰逻辑见
/// TtsCacheManager）。
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

  /// 段内句子序号（0 起；朗读单元 = 句子，见 reading-sentence-highlight.md）。
  /// 缓存键 = article_paragraph_id + sentence_index + speed + voice_id；
  /// 旧库补列时同时清空旧段落级缓存（database.dart selfHealTtsSentenceColumn）。
  /// 无 DEFAULT（Room 建表纪律：默认值由应用代码填充）——旧库 ALTER 补列
  /// 必需的 `DEFAULT 0` 只出现在自愈 DDL 里（与 voice_id 同模式）。
  IntColumn get sentenceIndex => integer()();

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
