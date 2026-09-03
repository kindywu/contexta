import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/core/time/iso8601.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/seed/seed_database.dart';

/// Task 7 种子数据测试。
///
/// 对照 Android 原版 seedDatabase（SeedDatabase.kt）：
/// - 3 个历史批次（LOW / MEDIUM / HIGH），generated_on 固定 "2026-03-29"、
///   status='READY'、last_updated_at = isoOffsetDateTime(2026-03-29 12:00)
/// - 每批 5 篇已完成文章（共 15）：status='SUCCESS'、retry_count=0、
///   max_retries=3、accumulated_read_seconds=0、generation_completed_at=now
/// - 每篇文章的段落原样写入（共 105）
/// - user_settings 不写入（onCreate 只种阅读数据）
/// - article_batch 非空时不再写入（幂等）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('writeSeedIfNeeded', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('全新库写入种子：3 批次 / 15 文章 / 105 段落', () async {
      await writeSeedIfNeeded(db);

      final batches =
          await (db.select(db.articleBatches)..where((t) => t.generatedOn.equals('2026-03-29'))).get();
      expect(batches.length, 3);
      expect(batches.map((b) => b.status).toSet(), {'READY'});

      final articles = await db.select(db.articles).get();
      expect(articles.length, 15);
      expect((await db.select(db.articleParagraphs).get()).length, 105);
    });

    test('批次字段：LOW/MEDIUM/HIGH 难度、last_updated_at 为种子固定时刻', () async {
      await writeSeedIfNeeded(db);

      final batches = await db.select(db.articleBatches).get();
      expect(
        batches.map((b) => b.difficultyLevelSnapshot).toSet(),
        {'LOW', 'MEDIUM', 'HIGH'},
      );
      // 与 SeedDatabase.kt dateTimeStringAt(2026, 3, 29, 12, 0) 等价
      final seedNow = isoOffsetDateTime(DateTime(2026, 3, 29, 12, 0));
      expect(batches.map((b) => b.lastUpdatedAt).toSet(), {seedNow});
    });

    test('文章字段：SUCCESS / 阅读秒数 0 / 标题已填（T6 后无 retry/maxRetries/完成时间列）', () async {
      await writeSeedIfNeeded(db);

      final articles = await db.select(db.articles).get();
      expect(articles.map((a) => a.status).toSet(), {'SUCCESS'});
      expect(articles.every((a) => a.accumulatedReadSeconds == 0), isTrue);
      expect(articles.every((a) => a.title != null), isTrue);
    });

    test('文章按 orderIndex 归属批次：每批 5 篇、段落从 orderIndex 1 起连续', () async {
      await writeSeedIfNeeded(db);

      final batches = await db.select(db.articleBatches).get();
      for (final batch in batches) {
        final articles = await (db.select(db.articles)
              ..where((a) => a.batchId.equals(batch.id))
              ..orderBy([(a) => OrderingTerm.asc(a.orderIndex)]))
            .get();
        expect(articles.length, 5, reason: '批次 ${batch.difficultyLevelSnapshot} 应有 5 篇文章');
        expect(
          articles.map((a) => a.orderIndex).toList(),
          [1, 2, 3, 4, 5],
          reason: '批次 ${batch.difficultyLevelSnapshot} 文章顺序',
        );
        for (final article in articles) {
          final paras = await (db.select(db.articleParagraphs)
                ..where((p) => p.articleId.equals(article.id))
                ..orderBy([(p) => OrderingTerm.asc(p.orderIndex)]))
              .get();
          expect(
            paras.map((p) => p.orderIndex).toList(),
            List.generate(paras.length, (i) => i + 1),
            reason: '段落 orderIndex 应从 1 起连续',
          );
          expect(paras.every((p) => p.englishText.isNotEmpty), isTrue);
          expect(paras.every((p) => p.chineseTranslation.isNotEmpty), isTrue);
        }
      }
    });

    test('user_settings 不写入', () async {
      await writeSeedIfNeeded(db);

      expect(await db.select(db.userSettings).get(), isEmpty);
    });

    test('重复调用幂等：article_batch 非空时跳过', () async {
      await writeSeedIfNeeded(db);
      await writeSeedIfNeeded(db);

      expect((await db.select(db.articleBatches).get()).length, 3);
      expect((await db.select(db.articles).get()).length, 15);
      expect((await db.select(db.articleParagraphs).get()).length, 105);
    });

    test('种子译文无 U+FFFD 损坏字符（seed_articles.json 已修复）', () async {
      await writeSeedIfNeeded(db);

      final paras = await db.select(db.articleParagraphs).get();
      final allText = paras
          .map((p) => p.englishText + p.chineseTranslation)
          .join('\n');
      expect(allText.contains('�'), isFalse);
    });
  });
}
