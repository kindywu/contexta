import 'package:flutter/foundation.dart';

import '../background_work_scheduler.dart';
import '../model/article_batch.dart';
import '../repository/article_repository.dart';
import '../repository/settings_repository.dart';
import '../time/time_provider.dart';
import 'resend_pending_alerts_usecase.dart';
import 'trigger_next_batch_usecase.dart';

/// 启动编排结果（对照 Kotlin StartupOrchestrationUseCase.StartupResult）。
sealed class StartupResult {
  const StartupResult();
}

final class StartupPipelineBlocked extends StartupResult {
  const StartupPipelineBlocked();
}

final class StartupNeedsOnboarding extends StartupResult {
  const StartupNeedsOnboarding();
}

final class StartupReady extends StartupResult {
  const StartupReady();
}

final class StartupNeedsInitialBatch extends StartupResult {
  const StartupNeedsInitialBatch({required this.difficulty, required this.dailyCount});
  final String difficulty;
  final int dailyCount;
}

/// 应用启动时的编排逻辑：reconciliation、pipeline 解除阻塞、每日批次分配
/// （对照 Kotlin StartupOrchestrationUseCase.kt）。
///
/// **流程：**
/// 1. 检查 pipeline 是否阻塞 → 尝试恢复或返回阻塞状态
/// 2. 检查是否完成 onboarding → 返回 NeedsOnboarding
/// 3. 修复孤儿文章（重置 GENERATING/TIMEOUT/FAILED → PENDING）
/// 4. 重新调度所有卡在 GENERATING 状态的 batch 的 Worker
/// 5. 检查今天是否已有 daily_learning 分配 → Ready
/// 6. 查找 max(ref_batch_date) 之后的 READY 批次（严格晚于已消费日期，
///    不回头分配 seed 旧批次）
///    - 找到 → 分配给今天，触发下一批前置生成 → Ready
///    - 未找到 → NeedsInitialBatch（调用方创建并触发生成）
class StartupOrchestrationUseCase {
  StartupOrchestrationUseCase({
    required this._articleRepository,
    required this._settingsRepository,
    required this._timeProvider,
    required this._triggerNextBatch,
    required this._generationScheduler,
    required this._resendPendingAlerts,
  });

  final ArticleRepository _articleRepository;
  final SettingsRepository _settingsRepository;
  final TimeProvider _timeProvider;
  final TriggerNextBatchUseCase _triggerNextBatch;
  final BackgroundWorkScheduler _generationScheduler;
  final ResendPendingAlertsUseCase _resendPendingAlerts;

  /// Full startup routine: called once when the app opens.
  Future<StartupResult> call(int currentVersionCode) async {
    // 1. Check pipeline block
    if (await _articleRepository.isPipelineBlocked()) {
      final recovered =
          await _articleRepository.recoverIfNewerVersion(currentVersionCode);
      if (!recovered) return const StartupPipelineBlocked();
    }

    // 2. Check onboarding
    final settings = await _settingsRepository.getSettings();
    if (settings == null || !settings.isOnboarded) {
      return const StartupNeedsOnboarding();
    }

    // 3. 先查询卡在 GENERATING 的 batch（reconciliation 会重置它们）
    final stuckBatches = await _articleRepository.getGeneratingBatches();
    // Flutter 特有：worker 调度失败时批次可能永久卡在 PENDING（Kotlin 版
    // worker 入队总是成功）。启动时一并重新调度，KEEP 策略保证不重复。
    final pendingBatches = await _articleRepository.getPendingBatches();

    // 4. Reconcile orphan GENERATING/TIMEOUT/FAILED articles + reset GENERATING batches
    await _articleRepository.reconcileOrphanArticles();

    // 5. 重新调度之前卡死的 batch：
    //    reconcileOrphanArticles 已将孤儿文章和 batch 重置为 PENDING，
    //    这里重新 enqueue Worker 让它们重新被认领生成。
    for (final batch in [...stuckBatches, ...pendingBatches]) {
      debugPrint('[StartupOrch] re-scheduling batch ${batch.id} (status=${batch.status})');
      await _generationScheduler.scheduleBatchGeneration(batch.id);
    }

    // 5.5 补发未送达的飞书告警（生成期间进程被终止时，实时告警可能丢失）。
    //     失败不影响启动主流程——下次启动还会再试。
    try {
      await _resendPendingAlerts();
    } catch (_) {
      // 忽略：下次启动再试
    }

    final today = _timeProvider.todayDateString();

    // 6. Check if today already has a daily_learning assignment
    final todayBatch = await _articleRepository.getAssignedBatchForDate(today);
    if (todayBatch != null) {
      // 即使今天已有分配，仍需确保未来有预生成的批次可用。
      // 如果 daily_learning 引用的最后日期之后没有 READY 批次，则触发生成。
      await _triggerNextBatch(
        settings.difficultyLevel,
        settings.dailyArticleCount,
      );
      return const StartupReady();
    }

    // 7. Find next READY batch for the user's difficulty.
    //    只找已消费批次日期之后的批次（严格 >）：批次按时间顺序消费，
    //    不回头分配 seed 旧批次。
    final maxRefDate = await _articleRepository.getMaxRefBatchDate();
    final nextBatch = await _articleRepository.findNextReadyBatch(
      settings.difficultyLevel,
      maxRefDate,
    );

    if (nextBatch != null && nextBatch.status == BatchStatus.ready) {
      await _articleRepository.assignBatchForToday(
        nextBatch.id,
        nextBatch.generatedOn ?? today,
        settings.dailyArticleCount,
      );
      // 触发下一批的前置生成
      await _triggerNextBatch(
        settings.difficultyLevel,
        settings.dailyArticleCount,
      );
      return const StartupReady();
    }

    // 8. No READY batch available - need to create and generate one
    return StartupNeedsInitialBatch(
      difficulty: settings.difficultyLevel,
      dailyCount: settings.dailyArticleCount,
    );
  }
}
