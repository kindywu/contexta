import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/tts/tts_cache_manager.dart';
import 'package:contexta/domain/model/tts_voice.dart';

/// TtsCacheManager 测试：缓存键含音色维度（同段同速不同音色互不串音）。
///
/// brief 测试未处理路径注入：_dir 走 getApplicationSupportDirectory()（path_provider
/// 插件通道），flutter test 无宿主通道会抛 MissingPluginException——故注入
/// cacheDirectoryOverride（临时目录），决策记录见 task-4-report.md。

void main() {
  late AppDatabase db;
  late TtsCacheManager manager;
  late Directory tmpDir;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tmpDir = Directory.systemTemp.createTempSync('tts_cache_test');
    manager = TtsCacheManager(
      db: db,
      storageCapBytes: 100 * 1024 * 1024,
      cacheDirectoryOverride: tmpDir,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('同段同速不同音色 → 不同缓存（互不串音）', () async {
    final p1 = await manager.writeParagraph(
        paragraphId: 1, wavData: [1, 2, 3], speed: 1.0, voice: TtsVoice.bella);
    final p2 = await manager.writeParagraph(
        paragraphId: 1, wavData: [4, 5, 6], speed: 1.0, voice: TtsVoice.hugo);

    expect(p1, isNot(p2)); // 文件名含音色
    expect(await manager.lookupParagraph(1, 1.0, TtsVoice.bella), p1);
    expect(await manager.lookupParagraph(1, 1.0, TtsVoice.hugo), p2);
    expect(await manager.needsGenerate(1, 1.0, TtsVoice.bella), isFalse);
    expect(await manager.needsGenerate(1, 1.0, TtsVoice.leo), isTrue);
  });

  test('writeParagraph 同键去重（重复写不产生两行）', () async {
    await manager.writeParagraph(
        paragraphId: 2, wavData: [1], speed: 0.8, voice: TtsVoice.luna);
    await manager.writeParagraph(
        paragraphId: 2, wavData: [2], speed: 0.8, voice: TtsVoice.luna);
    final rows = await (db.select(db.ttsCaches)).get();
    expect(rows.where((r) => r.articleParagraphId == 2).length, 1);
    expect(rows.first.voiceId, 'LUNA');
  });

  test('lookupArticleParagraphs 按音色过滤', () async {
    await manager.writeParagraph(
        paragraphId: 3, wavData: [1], speed: 1.0, voice: TtsVoice.bella);
    final hits = await manager.lookupArticleParagraphs(
        [3], 1.0, TtsVoice.hugo);
    expect(hits, isEmpty);
    final hitsBella = await manager.lookupArticleParagraphs(
        [3], 1.0, TtsVoice.bella);
    expect(hitsBella.keys, [3]);
  });
}
