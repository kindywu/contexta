import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';
import 'package:contexta/data/remote/dto/article_dto.dart';
import 'package:contexta/data/sync/sync_articles_usecase.dart';
import 'package:contexta/domain/time/time_provider.dart';

/// Task 4（计划 B）：每日文章同步幂等测试。
///
/// SyncArticlesUseCase 直连 drift DAO（裁定：不走 ArticleRepository 大接口），
/// fetchToday 函数注入——测试直接给假数据，不依赖网络 / ServerApiClient。
/// 7 个场景覆盖简报：首次同步、重复同步幂等、服务端更新、段落 upsert、
/// fetch 失败 / 空列表、难度分组、generatedOn = 服务端 target_date。
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

  /// 3 难度（LOW/MEDIUM/HIGH）各 5 篇，共 15 篇，每篇 2 段。
  List<ArticleDto> buildTodayArticles({String targetDate = '2026-08-12'}) {
    final list = <ArticleDto>[];
    var id = 1;
    const groups = [('LOW', 'life'), ('MEDIUM', 'tech'), ('HIGH', 'science')];
    for (final (difficulty, category) in groups) {
      for (var i = 1; i <= 5; i++) {
        list.add(
          buildArticle(
            id: id,
            difficulty: difficulty,
            contentCategory: category,
            orderIndex: i,
            title: 'title-$difficulty-$i',
            targetDate: targetDate,
          ),
        );
        id++;
      }
    }
    return list;
  }

  SyncArticlesUseCase buildUseCase(
    Future<List<ArticleDto>> Function() fetch, {
    String now = '2026-08-13T09:00:00+08:00',
  }) {
    return SyncArticlesUseCase(
      db: db,
      batchDao: batchDao,
      articleDao: articleDao,
      paragraphDao: paragraphDao,
      fetchToday: fetch,
      timeProvider: _FakeTimeProvider(now),
    );
  }

  test('首次同步：3 难度各 5 篇 → 3 个 CURRENT 批次 + 15 篇 SUCCESS 文章 + 段落', () async {
    final result = await buildUseCase(() async => buildTodayArticles()).call();

    expect(result.syncedBatches, 3);
    expect(result.syncedArticles, 15);
    expect(result.skippedAuth, isFalse);

    final batches = await db.select(db.articleBatches).get();
    expect(batches, hasLength(3));
    final batchByDifficulty = <String, int>{};
    for (final b in batches) {
      expect(b.status, 'CURRENT', reason: '批次必须 CURRENT（简报裁定，非仓储 PENDING 默认）');
      expect(b.generatedOn, '2026-08-12');
      expect(['LOW', 'MEDIUM', 'HIGH'], contains(b.difficultyLevelSnapshot));
      batchByDifficulty[b.difficultyLevelSnapshot] = b.id;
    }

    final articles = await db.select(db.articles).get();
    expect(articles, hasLength(15));
    for (final a in articles) {
      expect(a.status, 'SUCCESS');
      expect(a.accumulatedReadSeconds, 0);
      expect(a.title, isNotNull);
      // server id 1-5 → LOW，6-10 → MEDIUM，11-15 → HIGH
      final serverId = a.serverArticleId!;
      final expectedDifficulty = switch (serverId) {
        <= 5 => 'LOW',
        <= 10 => 'MEDIUM',
        _ => 'HIGH',
      };
      final difficulty = batches
          .firstWhere((b) => b.id == a.batchId)
          .difficultyLevelSnapshot;
      expect(difficulty, expectedDifficulty, reason: '文章必须落在同难度批次');
      expect(a.contentCategory, switch (expectedDifficulty) {
        'LOW' => 'life',
        'MEDIUM' => 'tech',
        _ => 'science',
      });
      final orderInGroup = serverId % 5 == 0 ? 5 : serverId % 5;
      expect(a.orderIndex, orderInGroup);
      expect(a.title, 'title-$expectedDifficulty-$orderInGroup');
    }
    expect(batchByDifficulty.keys, hasLength(3));

    final paragraphs = await db.select(db.articleParagraphs).get();
    expect(paragraphs, hasLength(30), reason: '15 篇 × 2 段');
    for (final p in paragraphs) {
      expect(p.englishText, startsWith('para'));
      expect(p.chineseTranslation, startsWith('段落'));
      expect(p.orderIndex, inInclusiveRange(1, 2));
    }
  });

  test('重复同步（同数据）→ 行数不变（server_article_id 幂等）', () async {
    final uc = buildUseCase(() async => buildTodayArticles());
    await uc.call();
    final countBatch = (await db.select(db.articleBatches).get()).length;
    final countArticle = (await db.select(db.articles).get()).length;
    final countParagraph = (await db.select(db.articleParagraphs).get()).length;
    expect(countBatch, 3);
    expect(countArticle, 15);
    expect(countParagraph, 30);

    final result = await uc.call();
    expect(result.syncedBatches, 3);
    expect(result.syncedArticles, 15);
    expect(await db.select(db.articleBatches).get(), hasLength(countBatch));
    expect(await db.select(db.articles).get(), hasLength(countArticle));
    expect(
      await db.select(db.articleParagraphs).get(),
      hasLength(countParagraph),
    );
    // 批次仍只有 3 个 CURRENT（复用而非重建）
    for (final b in await db.select(db.articleBatches).get()) {
      expect(b.status, 'CURRENT');
    }
  });

  test('服务端更新 title/orderIndex → 二次同步更新不新增', () async {
    var data = buildTodayArticles();
    final uc = buildUseCase(() async => data);
    await uc.call();
    final countBefore = (await db.select(db.articles).get()).length;

    // 服务端改了 id=3 的 title 与顺序；id=1 保持不变
    data = [
      for (final a in data)
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
    ];

    await uc.call();
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
    var data = buildTodayArticles();
    final uc = buildUseCase(() async => data);
    await uc.call();
    final countBefore = (await db.select(db.articleParagraphs).get()).length;

    // 服务端改了 id=5 的段落文本（段数不变）→ 更新文本不增行
    // 服务端把 id=6 的段落从 2 段改成 1 段 → 先删后插，该文剩 1 段
    data = [
      for (final a in data)
        if (a.id == 5)
          ArticleDto(
            id: 5,
            targetDate: '2026-08-12',
            difficulty: 'LOW',
            contentCategory: 'life',
            orderIndex: 5,
            title: 'title-LOW-5',
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
                englishText: 'para2-of-5',
                chineseTranslation: '段落2-5',
              ),
            ],
          )
        else if (a.id == 6)
          buildArticle(
            id: 6,
            difficulty: 'MEDIUM',
            contentCategory: 'tech',
            orderIndex: 1,
            title: 'title-MEDIUM-1',
            paragraphCount: 1,
          )
        else
          a,
    ];

    await uc.call();
    expect(
      await db.select(db.articleParagraphs).get(),
      hasLength(countBefore - 1),
      reason: 'id=6 少一段；其余不重复',
    );
    final article5 = await articlesByServerId(db, 5);
    final paras5 = await paragraphDao.getByArticle(article5!.id);
    expect(paras5, hasLength(2));
    expect(paras5[0].englishText, 'revised-para');
    expect(paras5[0].chineseTranslation, '修订段落');
    expect(paras5[1].englishText, 'para2-of-5');
    final article6 = await articlesByServerId(db, 6);
    final paras6 = await paragraphDao.getByArticle(article6!.id);
    expect(paras6, hasLength(1));
    expect(paras6[0].englishText, 'para1-of-6');
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

    var data = buildTodayArticles();
    final uc = buildUseCase(() async => data);
    await uc.call();

    // 服务端更新 id=3 的 title，且其段落含 'boom' → 段落插入失败
    data = [
      for (final a in data)
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
    ];

    await expectLater(uc.call(), throwsA(isA<SqliteException>()));
    // 回滚：title 未更新、段落未丢、无半同步残留
    final article3 = await articlesByServerId(db, 3);
    expect(article3!.title, 'title-LOW-3');
    final paras3 = await paragraphDao.getByArticle(article3.id);
    expect(paras3, hasLength(2));
    expect(paras3[0].englishText, 'para1-of-3');
    expect(paras3[1].englishText, 'para2-of-3');
    expect(await db.select(db.articles).get(), hasLength(15));
    expect(await db.select(db.articleParagraphs).get(), hasLength(30));
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
      return buildTodayArticles();
    });

    final results = await Future.wait([uc.call(), uc.call()]);
    expect(fetchCount, 1, reason: '单飞：并发调用复用同一 in-flight Future');
    expect(results[0].syncedBatches, 3);
    expect(results[0].syncedArticles, 15);
    expect(results[1].syncedBatches, 3);
    expect(results[1].syncedArticles, 15);
    // 无双插：行数与单次一致（若无双飞保护，双 _ensureBatch 会撞
    // UNIQUE(difficulty, generated_on) 抛 SqliteException）
    expect(await db.select(db.articleBatches).get(), hasLength(3));
    expect(await db.select(db.articles).get(), hasLength(15));
    expect(await db.select(db.articleParagraphs).get(), hasLength(30));
  });

  test('fetch 失败后 in-flight 清理：下一次同步恢复正常', () async {
    var fail = true;
    final uc = buildUseCase(() async {
      if (fail) throw StateError('boom');
      return buildTodayArticles();
    });

    await expectLater(uc.call(), throwsStateError);
    fail = false;
    final result = await uc.call();
    expect(result.syncedBatches, 3);
    expect(result.syncedArticles, 15);
    expect(await db.select(db.articles).get(), hasLength(15));
  });

  test('空列表 → 0 批次 0 文章', () async {
    final result = await buildUseCase(() async => []).call();
    expect(result.syncedBatches, 0);
    expect(result.syncedArticles, 0);
    expect(await db.select(db.articleBatches).get(), isEmpty);
    expect(await db.select(db.articles).get(), isEmpty);
  });

  test('批次难度分组正确：输入乱序也按 difficulty 分组', () async {
    // 乱序输入：HIGH 在前、LOW 在后、MEDIUM 夹中间
    final shuffled = <ArticleDto>[
      for (var i = 1; i <= 2; i++)
        buildArticle(
          id: 10 + i,
          difficulty: 'HIGH',
          contentCategory: 'science',
          orderIndex: i,
          title: 'h$i',
        ),
      buildArticle(
        id: 6,
        difficulty: 'MEDIUM',
        contentCategory: 'tech',
        orderIndex: 1,
        title: 'm1',
      ),
      for (var i = 1; i <= 2; i++)
        buildArticle(
          id: i,
          difficulty: 'LOW',
          contentCategory: 'life',
          orderIndex: i,
          title: 'l$i',
        ),
      buildArticle(
        id: 7,
        difficulty: 'MEDIUM',
        contentCategory: 'tech',
        orderIndex: 2,
        title: 'm2',
      ),
    ];

    final result = await buildUseCase(() async => shuffled).call();
    expect(result.syncedBatches, 3);
    expect(result.syncedArticles, shuffled.length);

    final batches = await db.select(db.articleBatches).get();
    expect(batches, hasLength(3));
    final batchByDifficulty = {
      for (final b in batches) b.difficultyLevelSnapshot: b.id,
    };
    expect(batchByDifficulty.keys, containsAll(['LOW', 'MEDIUM', 'HIGH']));
    for (final a in await db.select(db.articles).get()) {
      final difficulty = batches
          .firstWhere((b) => b.id == a.batchId)
          .difficultyLevelSnapshot;
      final serverId = a.serverArticleId!;
      expect(difficulty, switch (serverId) {
        <= 5 => 'LOW',
        <= 10 => 'MEDIUM',
        _ => 'HIGH',
      });
    }
  });

  test('generatedOn = 服务端 target_date（不是本地 today——跨日同步语义）', () async {
    // 服务端返回 08-10 的文章（服务器时区/延迟），本地时钟已是 08-13
    final uc = buildUseCase(
      () async => buildTodayArticles(targetDate: '2026-08-10'),
    );
    await uc.call();
    final batches = await db.select(db.articleBatches).get();
    expect(batches, hasLength(3));
    for (final b in batches) {
      expect(b.generatedOn, '2026-08-10');
    }
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
