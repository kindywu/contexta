import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/tts/tts_cache_manager.dart';
import 'package:contexta/domain/model/tts_voice.dart';

/// TtsCacheManager 测试：句子级缓存键（段落 ID + 段内句序号 + 语速 + 音色），
/// 同段不同句、同句不同音色互不串音。
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

  test('同句同速不同音色 → 不同缓存（互不串音）', () async {
    final p1 = await manager.writeSentence(
      paragraphId: 1, sentenceIndex: 0, wavData: [1, 2, 3],
      speed: 1.0, voice: TtsVoice.bella,
    );
    final p2 = await manager.writeSentence(
      paragraphId: 1, sentenceIndex: 0, wavData: [4, 5, 6],
      speed: 1.0, voice: TtsVoice.hugo,
    );

    expect(p1, isNot(p2)); // 文件名含音色
    expect(
      await manager.lookupSentence(
        paragraphId: 1, sentenceIndex: 0, speed: 1.0, voice: TtsVoice.bella,
      ),
      p1,
    );
    expect(
      await manager.lookupSentence(
        paragraphId: 1, sentenceIndex: 0, speed: 1.0, voice: TtsVoice.hugo,
      ),
      p2,
    );
    expect(
      await manager.needsGenerateSentence(
        paragraphId: 1, sentenceIndex: 0, speed: 1.0, voice: TtsVoice.bella,
      ),
      isFalse,
    );
    expect(
      await manager.needsGenerateSentence(
        paragraphId: 1, sentenceIndex: 0, speed: 1.0, voice: TtsVoice.leo,
      ),
      isTrue,
    );
  });

  test('同段不同句 → 各自缓存（句子级粒度）', () async {
    final s0 = await manager.writeSentence(
      paragraphId: 5, sentenceIndex: 0, wavData: [1],
      speed: 1.0, voice: TtsVoice.bella,
    );
    final s1 = await manager.writeSentence(
      paragraphId: 5, sentenceIndex: 1, wavData: [2],
      speed: 1.0, voice: TtsVoice.bella,
    );

    expect(s0, isNot(s1));
    expect(
      await manager.lookupSentence(
        paragraphId: 5, sentenceIndex: 1, speed: 1.0, voice: TtsVoice.bella,
      ),
      s1,
    );
    expect(
      await manager.needsGenerateSentence(
        paragraphId: 5, sentenceIndex: 0, speed: 1.0, voice: TtsVoice.bella,
      ),
      isFalse,
    );
  });

  test('writeSentence 同键去重（重复写不产生两行）', () async {
    await manager.writeSentence(
      paragraphId: 2, sentenceIndex: 3, wavData: [1],
      speed: 0.8, voice: TtsVoice.luna,
    );
    await manager.writeSentence(
      paragraphId: 2, sentenceIndex: 3, wavData: [2],
      speed: 0.8, voice: TtsVoice.luna,
    );
    final rows = await (db.select(db.ttsCaches)).get();
    expect(rows.length, 1);
    expect(rows.first.articleParagraphId, 2);
    expect(rows.first.sentenceIndex, 3);
    expect(rows.first.voiceId, 'LUNA');
  });

  test('缓存文件丢失 → 视为需生成并清理 DB 行', () async {
    final path = await manager.writeSentence(
      paragraphId: 4, sentenceIndex: 0, wavData: [1],
      speed: 1.0, voice: TtsVoice.bella,
    );
    File(path).deleteSync();

    expect(
      await manager.lookupSentence(
        paragraphId: 4, sentenceIndex: 0, speed: 1.0, voice: TtsVoice.bella,
      ),
      isNull,
    );
    expect(await (db.select(db.ttsCaches)).get(), isEmpty);
  });
}
