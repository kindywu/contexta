import 'package:flutter/foundation.dart';

import '../../data/sync/sync_articles_usecase.dart';
import '../repository/article_repository.dart';
import '../repository/settings_repository.dart';
import '../time/time_provider.dart';

/// 启动编排结果（服务端同步模型）。
sealed class StartupResult {
  const StartupResult();
}

/// 未完成 onboarding——首页展示引导，不触发同步。
final class StartupNeedsOnboarding extends StartupResult {
  const StartupNeedsOnboarding();
}

/// 已 onboarding 但无 token——同步跳过，首页仍可浏览本地文章
/// （「未登录」横幅提供登录入口）。
final class StartupNeedsLogin extends StartupResult {
  const StartupNeedsLogin();
}

/// 同步已执行（或降级跳过）——首页正常加载。
///
/// [syncedBatches]：本次同步覆盖的批次数（复用 + 新建）；同步失败时为 0，
/// 首页不阻塞（历史文章可读）。
final class StartupReady extends StartupResult {
  const StartupReady({required this.syncedBatches});
  final int syncedBatches;
}

/// 应用启动编排（服务端同步模型，2026-08-13 计划 B Task 5 重写）。
///
/// **流程：**
/// 1. onboarding 检查 → 未完成 → [StartupNeedsOnboarding]（不触发同步）
/// 2. 登录态检查 → 无 token → [StartupNeedsLogin]（同步跳过，首页仍可用）
/// 3. [SyncArticlesUseCase] 每日同步（失败降级：warn + 继续，不阻塞首页）
/// 4. 今天无 daily_learning → 按用户难度找今天批次
///    [ArticleRepository.getBatchByDifficultyAndDate]（同步按
///    (difficulty, generatedOn=服务端 target_date) 建批次）→
///    [ArticleRepository.assignBatchForToday]
///    （dailyCountSnapshot = settings.dailyArticleCount）
/// 5. 返回 [StartupReady]（携带本次同步批次数）
///
/// 已删除（本地生成管道语义，见 B-T6 整体移除）：pipeline 阻塞检查、
/// 孤儿修复、GENERATING 重调度、飞书告警补发、trigger_next_batch 前置生成。
class StartupOrchestrationUseCase {
  StartupOrchestrationUseCase({
    required this._articleRepository,
    required this._settingsRepository,
    required this._timeProvider,
    required this._syncArticles,
  });

  final ArticleRepository _articleRepository;
  final SettingsRepository _settingsRepository;
  final TimeProvider _timeProvider;
  final SyncArticlesUseCase _syncArticles;

  /// Full startup routine: called once when the app opens（首页 load /
  /// 下拉刷新共用；幂等——已分配过则跳过分配步骤）。
  Future<StartupResult> call() async {
    // 1. Onboarding check
    final settings = await _settingsRepository.getSettings();
    if (settings == null || !settings.isOnboarded) {
      return const StartupNeedsOnboarding();
    }

    // 2. Login check（无 token → 同步跳过，本地模式可用）
    final token = settings.serverToken;
    if (token == null || token.isEmpty) {
      return const StartupNeedsLogin();
    }

    // 3. 每日同步（失败降级：warn + Ready(0)，不阻塞首页）
    var syncedBatches = 0;
    try {
      final result = await _syncArticles();
      syncedBatches = result.syncedBatches;
    } catch (e) {
      debugPrint('[StartupOrch] 同步失败，降级为本地模式: $e');
      return StartupReady(syncedBatches: 0);
    }

    // 4. 今天无 daily_learning → 按用户难度找今天批次分配
    //    （同步批次 status=CURRENT；首页按 daily_learning.ref_batch_id
    //    取文章，不校验批次状态，CURRENT 可正常展示）
    final today = _timeProvider.todayDateString();
    final assigned = await _articleRepository.getAssignedBatchForDate(today);
    if (assigned == null) {
      final todayBatch = await _articleRepository.getBatchByDifficultyAndDate(
        settings.difficultyLevel,
        today,
      );
      if (todayBatch != null) {
        await _articleRepository.assignBatchForToday(
          todayBatch.id,
          todayBatch.generatedOn ?? today,
          settings.dailyArticleCount,
        );
      }
    }

    // 5. Ready（首页正常加载本地文章）
    return StartupReady(syncedBatches: syncedBatches);
  }
}
