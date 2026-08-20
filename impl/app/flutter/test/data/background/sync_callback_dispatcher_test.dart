import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/background/sync_callback_dispatcher.dart';
import 'package:contexta/data/local/database.dart';
import 'package:contexta/data/local/daos/article_daos.dart';
import 'package:contexta/data/remote/dto/article_dto.dart';
import 'package:contexta/data/sync/sync_articles_usecase.dart';
import 'package:contexta/domain/time/time_provider.dart';

/// Task 8（计划 B）：后台每日同步 dispatcher 测试。
///
/// 可测设计：任务核心 [handleDailySyncTask] 的组装函数为参数注入（测试给
/// fake 组装函数；生产 [syncCallbackDispatcher] 用 [buildSyncUseCase]）。
/// 用真实 SyncArticlesUseCase + 内存库 + fake fetchToday 验证「确实同步」，
/// 比 mock use case 更贴近 T4 的直连 DAO 测试风格。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ArticleDto buildArticle({int id = 1}) => ArticleDto(
    id: id,
    targetDate: '2026-08-13',
    difficulty: 'MEDIUM',
    contentCategory: 'tech',
    orderIndex: 1,
    title: '同步文章$id',
    status: 'SUCCESS',
    regenerateCount: 0,
    paragraphs: const [
      ArticleParagraphDto(
        orderIndex: 1,
        englishText: 'Hello',
        chineseTranslation: '你好',
      ),
    ],
  );

  SyncArticlesUseCase buildUseCase(
    AppDatabase db,
    Future<List<ArticleDto>> Function() fetch,
  ) {
    return SyncArticlesUseCase(
      db: db,
      batchDao: ArticleBatchDao(db),
      articleDao: ArticleDao(db),
      paragraphDao: ArticleParagraphDao(db),
      fetchToday: fetch,
      timeProvider: _FakeTimeProvider(),
    );
  }

  test('任务名 dailyArticleSync → 调 SyncArticlesUseCase 真实同步并返回 true', () async {
    // 文件库而非内存库：handleDailySyncTask 在 finally 关闭数据库
    // （后台 isolate 句柄纪律，旧 dispatcher 同款），需重开连接断言
    final dir = await Directory.systemTemp.createTemp('sync_dispatcher_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.db');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final useCase = buildUseCase(db, () async => [buildArticle()]);

    final result = await handleDailySyncTask(dailySyncTaskName, () async => useCase);

    expect(result, isTrue);
    // 确认真实同步了（不是空跑）：重开连接断言批次 + 文章 + 段落落库
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(await reopened.select(reopened.articleBatches).get(), hasLength(1));
    expect(await reopened.select(reopened.articles).get(), hasLength(1));
    expect(await reopened.select(reopened.articleParagraphs).get(), hasLength(1));
  });

  test('未知任务名 → 不调组装函数，直接返回 true', () async {
    var built = false;
    final result = await handleDailySyncTask('someOtherTask', () async {
      built = true;
      return null;
    });

    expect(result, isTrue);
    expect(built, isFalse, reason: '未知任务不进入同步组装');
  });

  test('同步失败（fetch 抛）→ 静默吞掉不向上抛，返回 true', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final useCase = buildUseCase(db, () async => throw StateError('fetch boom'));

    final result = await handleDailySyncTask(dailySyncTaskName, () async => useCase);

    expect(result, isTrue);
    // 行级「失败不写行」断言在 sync_articles_usecase_test 覆盖（fetch 失败 → 不写任何行）
  });

  test('无 token（skippedAuth）→ 组装函数返回 null，跳过同步正常返回 true', () async {
    // 生产路径：buildSyncUseCase 读到 user_settings 无 server_token 时返回
    // null（skippedAuth 语义，不发无认证请求）。handler 对 null 的契约：
    // 跳过同步、正常返回 true（此时没有 use case 可调用）。
    var built = false;
    final result = await handleDailySyncTask(dailySyncTaskName, () async {
      built = true;
      return null;
    });

    expect(result, isTrue);
    expect(built, isTrue, reason: '组装函数被调用但同步被跳过');
  });

  test('组装失败（builder 抛）→ 静默吞掉，返回 true（不重试风暴）', () async {
    final result = await handleDailySyncTask(
      dailySyncTaskName,
      () async => throw StateError('assemble boom'),
    );

    expect(result, isTrue);
  });
}

/// 固定时钟（lastUpdatedAt 断言用不上精确值，给固定字符串即可）。
class _FakeTimeProvider implements TimeProvider {
  @override
  int nowMillis() => 0;

  @override
  String nowDateTimeString() => '2026-08-13T09:00:00+08:00';

  @override
  String todayDateString() => '2026-08-13';

  @override
  String nextDateString() => '2026-08-14';
}
