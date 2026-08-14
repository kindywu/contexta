import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/app_config.dart';
import '../../domain/time/prod_time_provider.dart';
import '../local/database_open.dart';
import '../local/daos/article_daos.dart';
import '../local/daos/settings_daos.dart';
import '../remote/article_api.dart';
import '../remote/server_api_client.dart';
import '../sync/sync_articles_usecase.dart';

/// 后台每日同步任务名（`registerPeriodicTask` 的 uniqueName 与 taskName 同名，
/// 均为此值；执行侧按 taskName 匹配）。
const dailySyncTaskName = 'dailyArticleSync';

/// 组装函数：后台 isolate 内打开数据库 + 读 token + 组装
/// [SyncArticlesUseCase]。返回 null = 未登录（user_settings 无 server_token），
/// 跳过本次同步（skippedAuth 语义，不发无认证请求）。失败向上抛
/// （[handleDailySyncTask] 统一静默处理）。
typedef SyncUseCaseBuilder = Future<SyncArticlesUseCase?> Function();

/// 测试注入点：生产恒为 null（[syncCallbackDispatcher] 回退到
/// [buildSyncUseCase]）；测试替换为 fake 组装函数（T8 可测设计，
/// 仿 T7 的 fake 注入模式）。
SyncUseCaseBuilder? syncUseCaseBuilderOverride;

/// 组装每日同步用例（纯构造注入，无 riverpod——后台 isolate 不开
/// ProviderContainer，直连 DAO，与 SyncArticlesUseCase 的直连 DAO 设计一致）。
///
/// - 数据库：复用生产 [buildAppDatabase]（asset 预置库复制 + WAL /
///   busy_timeout / foreign_keys + db_version 与补列自愈，与 UI 打开路径一致；
///   path_provider 在 workmanager 的 headless engine 中可用，旧 dispatcher
///   同款模式）；
/// - token：从 user_settings 读 server_token，无则跳过（null 返回）；
/// - 网络栈：Dio + [ServerApiClient]（envelope 解包 + Bearer 注入），
///   timeout 对齐 providers.dart 的 serverApiClientProvider。
/// - 生命周期：本函数内打开的数据库，成功路径交由调用方
///   （[handleDailySyncTask] finally）关闭；失败路径在此 close 后 rethrow。
Future<SyncArticlesUseCase?> buildSyncUseCase() async {
  final db = await buildAppDatabase();
  try {
    final settings = await UserSettingsDao(db).get();
    final token = settings?.serverToken;
    if (token == null || token.isEmpty) {
      debugPrint('[SyncDispatcher] 未登录（无 token），跳过今日同步');
      await db.close();
      return null;
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
      ),
    );
    final apiClient = ServerApiClient(
      dio,
      baseUrl: AppConfig.serverBaseUrl,
      tokenProvider: () async => token,
    );
    return SyncArticlesUseCase(
      db: db,
      batchDao: ArticleBatchDao(db),
      articleDao: ArticleDao(db),
      paragraphDao: ArticleParagraphDao(db),
      fetchToday: () => ArticleApi(apiClient).fetchTodayArticles(),
      timeProvider: ProdTimeProvider(),
    );
  } catch (_) {
    await db.close();
    rethrow;
  }
}

/// 任务处理核心（可测：taskName 与组装函数均为参数，测试注入 fake）。
///
/// 语义：
/// - 任务名不匹配 → 直接 true（未知任务不处理，不崩溃）；
/// - 组装失败 / 同步失败 → 静默吞掉返回 true（Workmanager 不重试风暴，
///   失败等下一次周期窗口）；
/// - 无 token（组装函数返回 null）→ 跳过同步，正常返回 true（skippedAuth）。
Future<bool> handleDailySyncTask(
  String taskName,
  SyncUseCaseBuilder buildUseCase,
) async {
  if (taskName != dailySyncTaskName) {
    debugPrint('[SyncDispatcher] unknown task: $taskName');
    return true;
  }
  SyncArticlesUseCase? useCase;
  try {
    useCase = await buildUseCase();
    if (useCase == null) {
      debugPrint('[SyncDispatcher] skippedAuth：未登录，跳过本次同步');
      return true;
    }
    final result = await useCase.call();
    debugPrint(
      '[SyncDispatcher] sync done: '
      'batches=${result.syncedBatches} articles=${result.syncedArticles}',
    );
  } catch (e) {
    // 静默：后台任务失败不向上抛（Workmanager 会将其视为失败并重试，
    // 造成重试风暴；失败等下次周期即可）
    debugPrint('[SyncDispatcher] sync failed (silent): $e');
  } finally {
    // 关闭数据库连接，避免后台 isolate 泄漏句柄（旧 dispatcher 同款纪律；
    // skippedAuth 路径已由 buildSyncUseCase 自行关闭）
    await useCase?.db.close();
  }
  return true;
}

/// workmanager 回调派发器：后台 isolate 中由插件调用，执行每日文章同步。
///
/// 必须保持顶层函数 + `@pragma('vm:entry-point')`（后台 isolate 通过
/// entry point 发现它，不能被 tree-shake 掉）。本身只做薄接线：
/// executeTask → [handleDailySyncTask]（组装函数可经
/// [syncUseCaseBuilderOverride] 注入，测试态）。
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  debugPrint('[SyncDispatcher] ENTER');
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint(
      '[SyncDispatcher] executeTask taskName=$taskName inputData=$inputData',
    );
    return handleDailySyncTask(
      taskName,
      syncUseCaseBuilderOverride ?? buildSyncUseCase,
    );
  });
}
