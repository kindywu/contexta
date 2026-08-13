import 'package:drift/drift.dart' hide isNull, isNotNull;

import '../../domain/time/time_provider.dart';
import '../local/database.dart';
import '../local/daos/article_daos.dart';
import '../remote/dto/article_dto.dart';

/// 每日同步结果（T6 编排消费）。
class SyncResult {
  const SyncResult({
    required this.syncedBatches,
    required this.syncedArticles,
    required this.skippedAuth,
  });

  /// 复用 + 新建的批次总数（= 本次同步覆盖的难度数）。
  final int syncedBatches;

  /// 本次 upsert 的文章数（含更新与新增）。
  final int syncedArticles;

  /// 预留：认证未就绪时跳过同步的标记。当前恒 false（未登录不触发本用例，
  /// 登录守卫在上层）；将来若编排层需要区分「跳过」与「同步 0 篇」再启用。
  final bool skippedAuth;
}

/// 每日文章同步用例（幂等 upsert）。
///
/// 语义（简报裁定）：
/// - **批次**：按 (difficulty, generatedOn=服务端 target_date) 复用既有批次
///   （[ArticleBatchDao.getByDifficultyAndDate]；UNIQUE(difficulty, generated_on)
///   保证同日期同难度至多一批），无则创建 **CURRENT** 批次——注意不走
///   ArticleRepository.createBatch（其 status 默认 PENDING，属于本地生成
///   管道语义），直连 DAO 显式写 CURRENT；
/// - **文章**：按 server_article_id = dto.id 查本地行 → 有则更新
///   title/orderIndex/contentCategory（**不重置** accumulatedReadSeconds 等
///   本地阅读状态）→ 无则 INSERT（status 'SUCCESS'、accumulatedReadSeconds 0、
///   retryCount/maxRetries 0——同步文章不做本地重试，重试语义在服务端
///   regenerate_count，本任务不落库）；
/// - **段落**：先删该文章旧段落、再按 order_index 插入（(article_id,
///   order_index) 唯一索引保证重复同步不重复）；
/// - **事务性（2026-08-13 审查修复）**：每篇「文章更新/插入 + 段落先删后插」
///   包进单个 `db.transaction`——段落插入失败 / 进程中断整体回滚，不残留
///   「title 已更新、段落丢失」的半同步态（自愈不靠下次同步兜底）；
/// - **单飞（2026-08-13 审查修复）**：并发 call() 复用同一 in-flight Future
///   （仿 auth_service.ensureLoggedIn），失败也清理——否则并发双插批次
///   撞 UNIQUE(difficulty, generated_on) 抛 SqliteException；
/// - **时区**：generatedOn 用服务端 target_date，不是本地 today（跨日同步
///   语义：服务器审核通过日 = 批次日）。
///
/// 注入设计（简报裁定）：**直连 drift DAO**（ArticleBatchDao / ArticleDao /
/// ArticleParagraphDao）+ [db]（事务容器），不走 ArticleRepository 大接口
/// （避免为同步加方法污染抽象 + 全部 fake）；[fetchToday] 函数注入——测试
/// 给假数据，不依赖网络 / ServerApiClient。
class SyncArticlesUseCase {
  SyncArticlesUseCase({
    required this.db,
    required this.batchDao,
    required this.articleDao,
    required this.paragraphDao,
    required this.fetchToday,
    required this.timeProvider,
  });

  /// 事务容器（_upsertArticle 每篇一个事务）。
  final AppDatabase db;
  final ArticleBatchDao batchDao;
  final ArticleDao articleDao;
  final ArticleParagraphDao paragraphDao;
  final Future<List<ArticleDto>> Function() fetchToday;
  final TimeProvider timeProvider;

  /// 进行中的 call()（单飞：并发复用，完成后置空，失败同样清理）。
  Future<SyncResult>? _inflight;

  Future<SyncResult> call() {
    final inFlight = _inflight;
    if (inFlight != null) return inFlight;
    final future = _doCall();
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
  }

  Future<SyncResult> _doCall() async {
    final articles = await fetchToday();
    final byDifficulty = <String, List<ArticleDto>>{};
    for (final a in articles) {
      byDifficulty.putIfAbsent(a.difficulty, () => []).add(a);
    }
    var batches = 0, synced = 0;
    for (final entry in byDifficulty.entries) {
      // 同一接口返回的 target_date 一致（同一天），取组内首篇即可
      final batch = await _ensureBatch(entry.key, entry.value.first.targetDate);
      for (final dto in entry.value) {
        await _upsertArticle(batch.id, dto);
        synced++;
      }
      batches++;
    }
    return SyncResult(
      syncedBatches: batches,
      syncedArticles: synced,
      skippedAuth: false,
    );
  }

  /// 复用 (difficulty, generatedOn=date) 的既有批次，否则创建 CURRENT 批次。
  Future<ArticleBatchRow> _ensureBatch(String difficulty, String date) async {
    final existing = await batchDao.getByDifficultyAndDate(difficulty, date);
    if (existing != null) return existing;
    final id = await batchDao.insert(
      ArticleBatchesCompanion.insert(
        status: 'CURRENT',
        difficultyLevelSnapshot: difficulty,
        generatedOn: date,
        lastUpdatedAt: timeProvider.nowDateTimeString(),
      ),
    );
    final row = await batchDao.getById(id);
    if (row == null) {
      throw StateError('同步批次插入失败（difficulty=$difficulty, date=$date）');
    }
    return row;
  }

  /// server_article_id 幂等 upsert（见类注释）。
  ///
  /// 整篇（文章更新/插入 + 段落先删后插）包进单个事务：任一环节失败
  /// （如段落约束冲突）整体回滚——文章 title 不残留已更新、旧段落不丢失。
  Future<void> _upsertArticle(int batchId, ArticleDto dto) =>
      db.transaction(() async {
        final existing = await articleDao.getByServerArticleId(dto.id);
        if (existing == null) {
          final articleId = await articleDao.insert(
            ArticlesCompanion.insert(
              batchId: batchId,
              orderIndex: dto.orderIndex,
              contentCategory: dto.contentCategory,
              title: Value(dto.title),
              status: 'SUCCESS',
              retryCount: 0,
              accumulatedReadSeconds: 0,
              maxRetries: 0,
              serverArticleId: Value(dto.id),
            ),
          );
          await _replaceParagraphs(articleId, dto.paragraphs);
        } else {
          await articleDao.updateSyncedArticle(
            existing.id,
            title: dto.title,
            orderIndex: dto.orderIndex,
            contentCategory: dto.contentCategory,
          );
          await _replaceParagraphs(existing.id, dto.paragraphs);
        }
      });

  /// 段落先删后插：删除该文章旧段落，再按 order_index 插入新段落。
  Future<void> _replaceParagraphs(
    int articleId,
    List<ArticleParagraphDto> paragraphs,
  ) async {
    await paragraphDao.deleteByArticle(articleId);
    if (paragraphs.isEmpty) return;
    final entities = <ArticleParagraphsCompanion>[
      for (final p in paragraphs)
        ArticleParagraphsCompanion.insert(
          articleId: articleId,
          orderIndex: p.orderIndex,
          englishText: p.englishText,
          chineseTranslation: p.chineseTranslation,
        ),
    ];
    await paragraphDao.insertAll(entities);
  }
}
