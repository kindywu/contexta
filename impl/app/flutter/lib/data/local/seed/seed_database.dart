import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/time/iso8601.dart';
import '../database.dart';
import 'seed_article.dart';

/// 首次安装时写入种子数据（等价 Room onCreate 回调中的 seedDatabase）。
///
/// 对照 Android 原版 seed/SeedDatabase.kt：
/// - 3 个历史批次（LOW / MEDIUM / HIGH），日期固定为 2026-03-29，
///   每个批次 5 篇已完成文章（共 15 篇），作为用户打开 app 时的初始阅读内容
/// - 批次均为 READY（已生成完成的批次），等待启动编排将其分配到
///   当天的 daily_learning 表
/// - 批次/文章的时间字段用固定时刻 isoOffsetDateTime(2026-03-29 12:00)
///   （与原版 ContextaTypeConverters.dateTimeStringAt(2026, 3, 29, 12, 0) 等价）
///
/// 与原版差异（防御）：drift 的 MigrationStrategy.onCreate 只在新库触发，
/// 与 Room onCreate 语义一致，但这里仍先检查 article_batch 是否为空，
/// 避免任何路径下重复写入。
Future<void> writeSeedIfNeeded(AppDatabase db) async {
  // 表级空检查：非空则视为已种过种子，直接跳过
  if (await db.managers.articleBatches.count() > 0) return;

  final jsonText = await rootBundle.loadString('assets/seed_articles.json');
  final seedData =
      SeedData.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);

  final seedDate = '2026-03-29';
  // 种子批次是历史数据，完成时间取固定日期（手机时区），与 generated_on 保持一致
  final now = isoOffsetDateTime(DateTime(2026, 3, 29, 12, 0));

  await db.transaction(() async {
    // 事务内复查（并发安全）
    if (await db.managers.articleBatches.count() > 0) return;

    // 与原版 groupBy 一致：LinkedHashMap 保持 JSON 中的首次出现顺序
    final byDifficulty = <String, List<SeedArticle>>{};
    for (final article in seedData.seedArticles) {
      byDifficulty.putIfAbsent(article.difficultyLevel, () => []).add(article);
    }

    for (final MapEntry(key: difficulty, value: articles) in byDifficulty.entries) {
      final batchId = await db.into(db.articleBatches).insert(
            ArticleBatchesCompanion.insert(
              status: 'READY',
              difficultyLevelSnapshot: difficulty,
              generatedOn: seedDate,
              lastUpdatedAt: now,
            ),
          );
      if (batchId == -1) {
        throw StateError('Failed to insert seed batch for $difficulty');
      }

      // 与原版 articles.sortedBy { it.orderIndex } 一致
      articles.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final article in articles) {
        final articleId = await db.into(db.articles).insert(
              ArticlesCompanion.insert(
                batchId: batchId,
                orderIndex: article.orderIndex,
                contentCategory: article.contentCategory,
                title: Value(article.title),
                status: 'SUCCESS',
                generationCompletedAt: Value(now),
                retryCount: 0,
                accumulatedReadSeconds: 0,
                maxRetries: 3,
              ),
            );
        if (articleId == -1) {
          throw StateError('Failed to insert seed article: ${article.title}');
        }

        for (final para in article.paragraphs) {
          await db.into(db.articleParagraphs).insert(
                ArticleParagraphsCompanion.insert(
                  articleId: articleId,
                  orderIndex: para.orderIndex,
                  englishText: para.englishText,
                  chineseTranslation: para.chineseTranslation,
                ),
              );
        }
      }
    }
  });
}
