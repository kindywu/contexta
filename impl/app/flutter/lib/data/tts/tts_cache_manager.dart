import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/model/tts_voice.dart';
import '../local/database.dart';

/// TTS 音频缓存管理器：磁盘 WAV + DB 元数据 + FIFO 淘汰。
///
/// 命中 → 直接播文件；未命中 → 生成后写入缓存。
/// 缓存键 = 段落 ID + 段内句子序号 + 语速 + 音色：同一句同语速、不同音色各自
/// 缓存，互不串音。
/// FIFO 淘汰：总大小超 [storageCapBytes]（默认 50MB）时，按 lastAccessedAt
/// 升序逐条删除最旧条目（DB 行 + 磁盘文件）。
///
/// 启动时清理孤儿文件（DB 无记录但磁盘有）。
class TtsCacheManager {
  TtsCacheManager({
    required this.db,
    this.storageCapBytes = 50 * 1024 * 1024,
    this.cacheDirectoryOverride,
  });

  final AppDatabase db;
  final int storageCapBytes;

  /// 缓存目录注入（测试用临时目录；生产为 null 走 getApplicationSupportDirectory）。
  /// 对齐 KittenTtsEngine.modelBaseOverride 的注入模式。
  final Directory? cacheDirectoryOverride;

  Directory? _cacheDir;

  Future<Directory> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    if (cacheDirectoryOverride != null) {
      _cacheDir = cacheDirectoryOverride;
    } else {
      final root = await getApplicationSupportDirectory();
      _cacheDir = Directory('${root.path}/tts_cache');
    }
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    // 启动时清理孤儿文件
    await _cleanOrphanFiles();
    return _cacheDir!;
  }

  /// 句子缓存键（段落 ID + 段内句子序号 + 语速 + 音色）的 WHERE 条件。
  Expression<bool> _sentenceKey(
    int paragraphId,
    int sentenceIndex,
    double speed,
    TtsVoice voice,
  ) =>
      db.ttsCaches.articleParagraphId.equals(paragraphId) &
      db.ttsCaches.sentenceIndex.equals(sentenceIndex) &
      db.ttsCaches.speed.equals(speed) &
      db.ttsCaches.voiceId.equals(voice.dbValue);

  /// 按段落 ID + 段内句子序号 + 语速 + 音色查找缓存文件路径。
  ///
  /// 命中 → 更新 lastAccessedAt，返回文件路径。
  /// 未命中 → 返回 null。
  Future<String?> lookupSentence({
    required int paragraphId,
    required int sentenceIndex,
    required double speed,
    TtsVoice voice = TtsVoice.bella,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await (db.select(db.ttsCaches)
          ..where((_) => _sentenceKey(paragraphId, sentenceIndex, speed, voice)))
        .get();
    if (rows.isNotEmpty) {
      await (db.update(db.ttsCaches)
            ..where((t) => t.id.equals(rows.first.id)))
          .write(TtsCachesCompanion(lastAccessedAt: Value(now)));
      final path = rows.first.filePath;
      if (await File(path).exists()) return path;
      // 文件丢失：删除 DB 行
      await db.delete(db.ttsCaches).delete(rows.first);
      return null;
    }
    return null;
  }

  /// 写入句子缓存：WAV → 磁盘 + DB 行。
  ///
  /// 文件名含句序号与音色维度（同句同速不同音色 → 不同文件）。
  /// 写入后检查总大小，超 [storageCapBytes] 时执行 FIFO 淘汰。
  Future<String> writeSentence({
    required int paragraphId,
    required int sentenceIndex,
    required List<int> wavData,
    required double speed,
    TtsVoice voice = TtsVoice.bella,
  }) async {
    final dir = await _dir;
    final fileName = 'p_${paragraphId}_s$sentenceIndex'
        '_${speed.toStringAsFixed(2)}_${voice.dbValue}.wav';
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(wavData);

    final now = DateTime.now().millisecondsSinceEpoch;
    // 去重：先删同键旧行，防止并发生成插重复行
    await (db.delete(db.ttsCaches)
          ..where((_) => _sentenceKey(paragraphId, sentenceIndex, speed, voice)))
        .go();
    await db.into(db.ttsCaches).insert(
      TtsCachesCompanion(
        articleParagraphId: Value(paragraphId),
        sentenceIndex: Value(sentenceIndex),
        speed: Value(speed),
        voiceId: Value(voice.dbValue),
        filePath: Value(filePath),
        fileSize: Value(wavData.length),
        createdAt: Value(now),
        lastAccessedAt: Value(now),
      ),
    );

    // FIFO 淘汰检查
    await _evictIfNeeded(dir);

    return filePath;
  }

  /// 检查是否需要生成（该句该语速该音色无缓存或文件丢失）。
  Future<bool> needsGenerateSentence({
    required int paragraphId,
    required int sentenceIndex,
    required double speed,
    TtsVoice voice = TtsVoice.bella,
  }) async {
    final existing = await (db.select(db.ttsCaches)
          ..where((_) => _sentenceKey(paragraphId, sentenceIndex, speed, voice)))
        .get();
    if (existing.isEmpty) return true;
    return !(await File(existing.first.filePath).exists());
  }

  // ─── FIFO 淘汰 ───────────────────────────────────────────────────

  Future<void> _evictIfNeeded(Directory dir) async {
    final total = await _totalSize();
    if (total <= storageCapBytes) return;

    // 按 lastAccessedAt 升序逐条删除最旧条目
    final oldest = await (db.select(db.ttsCaches)
          ..orderBy([(t) => OrderingTerm(expression: t.lastAccessedAt)]))
        .getSingleOrNull();
    if (oldest == null) return;

    await _deleteCacheRow(oldest, dir);

    // 递归：删完再检查，直到总大小不超限
    await _evictIfNeeded(dir);
  }

  Future<int> _totalSize() async {
    final result = await db.customSelect(
      'SELECT COALESCE(SUM(file_size), 0) AS total FROM tts_cache',
    ).getSingle();
    return result.read<int>('total');
  }

  Future<void> _deleteCacheRow(TtsCacheRow row, Directory dir) async {
    await db.delete(db.ttsCaches).delete(row);
    try {
      final file = File(row.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 启动时：遍历缓存目录，删掉 DB 无记录的孤儿 WAV 文件。
  Future<void> _cleanOrphanFiles() async {
    final dir = await _dir;
    final entries = await dir.list().toList();
    final allRows = await db.select(db.ttsCaches).get();
    final knownPaths = allRows.map((r) => r.filePath).toSet();

    for (final entry in entries) {
      if (entry is File && entry.path.endsWith('.wav')) {
        if (!knownPaths.contains(entry.path)) {
          debugPrint('[TtsCache] cleaning orphan: ${entry.path}');
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
    }
  }
}
