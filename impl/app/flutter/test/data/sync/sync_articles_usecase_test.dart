import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';
import 'package:contexta/data/remote/dto/article_dto.dart';
import 'package:contexta/data/sync/sync_articles_usecase.dart';
import 'package:contexta/domain/time/time_provider.dart';

/// Task 5（计划 B）：SyncArticlesUseCase 按投放集同步测试。
///
/// SyncArticlesUseCase 直连 drift DAO（裁定：不走 ArticleRepository 大接口），
/// fetchDelivery 函数注入——测试直接给假数据，不依赖网络 / ServerApiClient。
/// 语义（简报裁定）：
/// - 批次键 = 投放日 delivery_date（非文章 target_date——投放集可跨天）；
/// - 空交付（articles 空）→ 0 批次 0 文章，不建批；
/// - 投放是一次性交付单难度，其余幂等 / 事务 / 单飞语义与计划 B 简报一致。
/// 10 个场景：首次投放、重复同步幂等、服务端更新、段落 upsert、事务回滚、
/// fetch 失败、并发单飞、in-flight 清理、空交付、generatedOn = delivery_date。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ArticleBatchDao batchDao;
  late ArticleDao articleDao;
  late ArticleParagraphDao paragraphDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    batchDao = ArticleBatchDao(db);
    articleDao = ArticleDao(db);
    paragraphDao = ArticleParagraphDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  ArticleDto buildArticle({
    required int id,
    required String difficulty,
    required String contentCategory,
    required int orderIndex,
    required String title,
    String targetDate = '2026-08-12',
    int paragraphCount = 2,
  }) {
    return ArticleDto(
      id: id,
      targetDate: targetDate,
      difficulty: difficulty,
      contentCategory: contentCategory,
      orderIndex: orderIndex,
      title: title,
      status: 'SUCCESS',
      regenerateCount: 0,
      paragraphs: [
        for (var i = 1; i <= paragraphCount; i++)
          ArticleParagraphDto(
            orderIndex: i,
            englishText: 'para$i-of-$id',
            chineseTranslation: '段落$i-$id',
          ),
      ],
    );
  }

  ArticleDeliveryDto buildDelivery({
    required List<ArticleDto> articles,
    String deliveryDate = '2026-08-13',
  }) => ArticleDeliveryDto(deliveryDate: deliveryDate, articles: articles);

  /// 单难度（LOW）3 篇（模拟一次投放集）。
  List<ArticleDto> buildDeliveryArticles({String deliveryDate = '2026-08-13'}) => [
    for (var i = 1; i <= 3; i++)
      buildArticle(
        id: i,
        difficulty: 'LOW',
        contentCategory: 'life',
        orderIndex: i,
        title: 'title-LOW-$i',
        targetDate: '2026-08-12',
        paragraphCount: 2,
      ),
  ];

  SyncArticlesUseCase buildUseCase(
    Future<ArticleDeliveryDto> Function() fetch, {
    String now = '2026-08-13T09:00:00+08:00',
  }) {
    return SyncArticlesUseCase(
      db: db,
      batchDao: batchDao,
      articleDao: articleDao,
      paragraphDao: paragraphDao,
      fetchDelivery: fetch,
      timeProvider: _FakeTimeProvider(now),
    );
  }

  test('首次投放：1 个 CURRENT 批次（generatedOn = delivery_date）+ 3 篇 SUCCESS + 段落', () async {
    final result = await buildUseCase(
      () async => buildDelivery(articles: buildDeliveryArticles()),
    ).call();

    expect(result.syncedBatches, 1);
    expect(result.syncedArticles, 3);
    expect(result.skippedAuth, isFalse);

    final batches = await db.select(db.articleBatches).get();
    expect(batches, hasLength(1));
    final batch = batches.single;
    expect(batch.status, 'CURRENT', reason: '批次必须 CURRENT（简报裁定，非仓储 PENDING 默认）');
    expect(batch.difficultyLevelSnapshot, 'LOW');
    // 批次键 = 投放日（delivery_date），不是文章 target_date（2026-08-12）
    expect(batch.generatedOn, '2026-08-13');

    final articles = await db.select(db.articles).get();
    expect(articles, hasLength(3));
    final byServerId = {for (final a in articles) a.serverArticleId!: a};
    for (var i = 1; i <= 3; i++) {
      final a = byServerId[i]!;
      expect(a.status, 'SUCCESS');
      expect(a.accumulatedReadSeconds, 0);
      expect(a.batchId, batch.id);
      expect(a.contentCategory, 'life');
      expect(a.orderIndex, i);
      expect(a.title, 'title-LOW-$i');
    }

    final paragraphs = await db.select(db.articleParagraphs).get();
    expect(paragraphs, hasLength(6), reason: '3 篇 × 2 段');
    for (final p in paragraphs) {
      expect(p.englishText, startsWith('para'));
      expect(p.chineseTranslation, startsWith('段落'));
      expect(p.orderIndex, inInclusiveRange(1, 2));
    }
  });

  test('重复同步（同数据）→ 行数不变（server_article_id 幂等）', () async {
    final uc = buildUseCase(
      () async => buildDelivery(articles: buildDeliveryArticles()),
    );
    await uc.call();
    final countBatch = (await db.select(db.articleBatches).get()).length;
    final countArticle = (await db.select(db.articles).get()).length;
    final countParagraph = (await db.select(db.articleParagraphs).get()).length;
    expect(countBatch, 1);
    expect(countArticle, 3);
    expect(countParagraph, 6);

    final result = await uc.call();
    expect(result.syncedBatches, 1);
    expect(result.syncedArticles, 3);
    expect(await db.select(db.articleBatches).get(), hasLength(countBatch));
    expect(await db.select(db.articles).get(), hasLength(countArticle));
    expect(
      await db.select(db.articleParagraphs).get(),
      hasLength(countParagraph),
    );
    // 批次仍只有 1 个 CURRENT（复用而非重建）
    for (final b in await db.select(db.articleBatches).get()) {
      expect(b.status, 'CURRENT');
    }
  });

  test('服务端更新 title/orderIndex → 二次同步更新不新增', () async {
    var data = buildDelivery(articles: buildDeliveryArticles());
    final uc = buildUseCase(() async => data);
    await uc.call();
    final countBefore = (await db.select(db.articles).get()).length;

    // 服务端改了 id=3 的 title 与顺序；id=1 保持不变
    data = buildDelivery(
      articles: [
        for (final a in buildDeliveryArticles())
          if (a.id == 3)
            buildArticle(
              id: 3,
              difficulty: 'LOW',
              contentCategory: 'life',
              orderIndex: 9,
              title: 'updated-title',
              paragraphCount: 1,
            )
          else
            a,
      ],
    );

    final result = await uc.call();
    expect(result.syncedBatches, 1);
    expect(result.syncedArticles, 3);
    final articles = await db.select(db.articles).get();
    expect(articles, hasLength(countBefore), reason: '更新不新增');
    final updated = articles.singleWhere((a) => a.serverArticleId == 3);
    expect(updated.title, 'updated-title');
    expect(updated.orderIndex, 9);
    expect(updated.accumulatedReadSeconds, 0, reason: '本地阅读时长不因同步重置');
    final untouched = articles.singleWhere((a) => a.serverArticleId == 1);
    expect(untouched.title, 'title-LOW-1');
  });

  test('段落 upsert：(article_id, order_index) 唯一——重复同步不重复、先删后插', () async {
    var data = buildDelivery(articles: buildDeliveryArticles());
    final uc = buildUseCase(() async => data);
    await uc.call();
    final countBefore = (await db.select(db.articleParagraphs).get()).length;
    expect(countBefore, 6);

    // 服务端改了 id=2 的段落文本（段数不变）→ 更新文本不增行
    // 服务端把 id=3 的段落从 2 段改成 1 段 → 先删后插，该文剩 1 段
    data = buildDelivery(
      articles: [
        for (final a in buildDeliveryArticles())
          if (a.id == 2)
            ArticleDto(
              id: 2,
              targetDate: '2026-08-12',
              difficulty: 'LOW',
              contentCategory: 'life',
              orderIndex: 2,
              title: 'title-LOW-2',
              status: 'SUCCESS',
              regenerateCount: 0,
              paragraphs: const [
                ArticleParagraphDto(
                  orderIndex: 1,
                  englishText: 'revised-para',
                  chineseTranslation: '修订段落',
                ),
                ArticleParagraphDto(
                  orderIndex: 2,
                  englishText: 'para2-of-2',
                  chineseTranslation: '段落2-2',
                ),
              ],
            )
          else if (a.id == 3)
            buildArticle(
              id: 3,
              difficulty: 'LOW',
              contentCategory: 'life',
              orderIndex: 3,
              title: 'title-LOW-3',
              paragraphCount: 1,
            )
          else
            a,
      ],
    );

    await uc.call();
    expect(
      await db.select(db.articleParagraphs).get(),
      hasLength(countBefore - 1),
      reason: 'id=3 少一段；其余不重复',
    );
    final article2 = await articlesByServerId(db, 2);
    final paras2 = await paragraphDao.getByArticle(article2!.id);
    expect(paras2, hasLength(2));
    expect(paras2[0].englishText, 'revised-para');
    expect(paras2[0].chineseTranslation, '修订段落');
    expect(paras2[1].englishText, 'para2-of-2');
    final article3 = await articlesByServerId(db, 3);
    final paras3 = await paragraphDao.getByArticle(article3!.id);
    expect(paras3, hasLength(1));
    expect(paras3[0].englishText, 'para1-of-3');
  });

  test('段落插入失败 → 整篇事务回滚（title 未更新、旧段落未丢）', () async {
    // 失败注入（真实 SQLite 约束路径）：english_text = 'boom' 的段落
    // 被触发器 RAISE(ABORT) 拒绝——比注入 fake hook 更贴近真实约束失败
    await db.customStatement('''
      CREATE TRIGGER fail_on_boom_paragraph
      BEFORE INSERT ON article_paragraph
      WHEN NEW.english_text = 'boom'
      BEGIN
        SELECT RAISE(ABORT, 'injected paragraph failure');
      END
    ''');

    var data = buildDelivery(articles: buildDeliveryArticles());
    final uc = buildUseCase(() async => data);
    await uc.call();

    // 服务端更新 id=3 的 title，且其段落含 'boom' → 段落插入失败
    data = buildDelivery(
      articles: [
        for (final a in buildDeliveryArticles())
          if (a.id == 3)
            ArticleDto(
              id: 3,
              targetDate: '2026-08-12',
              difficulty: 'LOW',
              contentCategory: 'life',
              orderIndex: 3,
              title: 'should-not-stick',
              status: 'SUCCESS',
              regenerateCount: 0,
              paragraphs: const [
                ArticleParagraphDto(
                  orderIndex: 1,
                  englishText: 'boom',
                  chineseTranslation: '触发',
                ),
                ArticleParagraphDto(
                  orderIndex: 2,
                  englishText: 'para2-of-3',
                  chineseTranslation: '段落2-3',
                ),
              ],
            )
          else
            a,
      ],
    );

    await expectLater(uc.call(), throwsA(isA<SqliteException>()));
    // 回滚：title 未更新、段落未丢、无半同步残留
    final article3 = await articlesByServerId(db, 3);
    expect(article3!.title, 'title-LOW-3');
    final paras3 = await paragraphDao.getByArticle(article3.id);
    expect(paras3, hasLength(2));
    expect(paras3[0].englishText, 'para1-of-3');
    expect(paras3[1].englishText, 'para2-of-3');
    expect(await db.select(db.articles).get(), hasLength(3));
    expect(await db.select(db.articleParagraphs).get(), hasLength(6));
  });

  test('fetch 失败 → 异常向上抛，不写任何行', () async {
    final uc = buildUseCase(() async => throw StateError('fetch boom'));
    await expectLater(uc.call(), throwsStateError);
    expect(await db.select(db.articleBatches).get(), isEmpty);
    expect(await db.select(db.articles).get(), isEmpty);
    expect(await db.select(db.articleParagraphs).get(), isEmpty);
  });

  test('并发 call() 单飞：Future.wait 两次 → fetch 只调 1 次、无双插', () async {
    var fetchCount = 0;
    final uc = buildUseCase(() async {
      fetchCount++;
      return buildDelivery(articles: buildDeliveryArticles());
    });

    final results = await Future.wait([uc.call(), uc.call()]);
    expect(fetchCount, 1, reason: '单飞：并发调用复用同一 in-flight Future');
    expect(results[0].syncedBatches, 1);
    expect(results[0].syncedArticles, 3);
    expect(results[1].syncedBatches, 1);
    expect(results[1].syncedArticles, 3);
    // 无双插：行数与单次一致（若无双飞保护，双 _ensureBatch 会撞
    // UNIQUE(difficulty, generated_on) 抛 SqliteException）
    expect(await db.select(db.articleBatches).get(), hasLength(1));
    expect(await db.select(db.articles).get(), hasLength(3));
    expect(await db.select(db.articleParagraphs).get(), hasLength(6));
  });

  test('fetch 失败后 in-flight 清理：下一次同步恢复正常', () async {
    var fail = true;
    final uc = buildUseCase(() async {
      if (fail) throw StateError('boom');
      return buildDelivery(articles: buildDeliveryArticles());
    });

    await expectLater(uc.call(), throwsStateError);
    fail = false;
    final result = await uc.call();
    expect(result.syncedBatches, 1);
    expect(result.syncedArticles, 3);
    expect(await db.select(db.articles).get(), hasLength(3));
  });

  test('空交付（articles: []）→ 0 批次 0 文章', () async {
    final result = await buildUseCase(
      () async => buildDelivery(articles: []),
    ).call();
    expect(result.syncedBatches, 0);
    expect(result.syncedArticles, 0);
    expect(await db.select(db.articleBatches).get(), isEmpty);
    expect(await db.select(db.articles).get(), isEmpty);
    expect(await db.select(db.articleParagraphs).get(), isEmpty);
  });

  test('generatedOn = delivery_date（不是文章 target_date——投放集可跨天）', () async {
    // 文章 target_date 是 08-10（审核通过日），投放集在 08-13 交付——
    // 批次必须落在 delivery_date，跨天投放不再各自成批
    final uc = buildUseCase(
      () async => buildDelivery(
        articles: [
          buildArticle(
            id: 1,
            difficulty: 'LOW',
            contentCategory: 'life',
            orderIndex: 1,
            title: 'title-LOW-1',
            targetDate: '2026-08-10',
          ),
        ],
        deliveryDate: '2026-08-13',
      ),
    );

    final result = await uc.call();
    expect(result.syncedBatches, 1);
    expect(result.syncedArticles, 1);
    final batches = await db.select(db.articleBatches).get();
    expect(batches, hasLength(1));
    expect(batches.single.generatedOn, '2026-08-13');
    expect(batches.single.difficultyLevelSnapshot, 'LOW');
  });

  group('ArticleDto.fromJson（服务端契约字段精确）', () {
    test('snake_case 全字段 + paragraphs 嵌套', () {
      final dto = ArticleDto.fromJson({
        'id': 42,
        'target_date': '2026-08-12',
        'difficulty': 'MEDIUM',
        'content_category': 'tech',
        'order_index': 3,
        'title': '标题',
        'status': 'SUCCESS',
        'regenerate_count': 2,
        'paragraphs': [
          {
            'order_index': 1,
            'english_text': 'Hello',
            'chinese_translation': '你好',
          },
        ],
      });
      expect(dto.id, 42);
      expect(dto.targetDate, '2026-08-12');
      expect(dto.difficulty, 'MEDIUM');
      expect(dto.contentCategory, 'tech');
      expect(dto.orderIndex, 3);
      expect(dto.title, '标题');
      expect(dto.status, 'SUCCESS');
      expect(dto.regenerateCount, 2);
      expect(dto.paragraphs, hasLength(1));
      expect(dto.paragraphs.single.orderIndex, 1);
      expect(dto.paragraphs.single.englishText, 'Hello');
      expect(dto.paragraphs.single.chineseTranslation, '你好');
    });
  });
}

/// 按服务端文章 id 查本地行（测试断言辅助）。
Future<ArticleRow?> articlesByServerId(AppDatabase db, int serverId) =>
    (db.select(
      db.articles,
    )..where((t) => t.serverArticleId.equals(serverId))).getSingleOrNull();

/// 固定时钟（nowDateTimeString 用于批次 lastUpdatedAt；today/next 断言
/// generatedOn 不取本地日期）。
class _FakeTimeProvider implements TimeProvider {
  _FakeTimeProvider(this._now);

  final String _now;

  @override
  int nowMillis() => 0;

  @override
  String nowDateTimeString() => _now;

  @override
  String todayDateString() => '2026-08-13';

  @override
  String nextDateString() => '2026-08-14';
}
