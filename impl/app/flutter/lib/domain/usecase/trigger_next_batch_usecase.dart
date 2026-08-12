import 'package:flutter/foundation.dart';

import '../background_work_scheduler.dart';
import '../repository/article_repository.dart';
import '../time/time_provider.dart';

/// 确保有未分配的 READY 批次可用（前置生成）（对照 Kotlin TriggerNextBatchUseCase.kt）。
///
/// **关键设计：生成数量与显示数量分离**
/// - [maxArticlesPerBatch] = 5，每个批次永远固定生成 5 篇文章
/// - 用户选择的 dailyCount 仅在分配批次时（[assignBatchForToday]）写入
///   `daily_learning.daily_count_snapshot`
/// - 首页显示时从 `daily_learning.daily_count_snapshot` 读取显示数量
///
/// **流程：**
/// 1. 检查是否有尚未被 [daily_learning] 引用的 READY 批次（匹配当前难度）
/// 2. 有 → 直接返回，无需操作
/// 3. 无 → 检查今天是否已为该难度创建过批次
/// 4. 有今日批次但未完成 → 跳过（Worker 继续）
/// 5. 无 → 创建新批次，触发生成 Worker
class TriggerNextBatchUseCase {
  TriggerNextBatchUseCase({
    required this._articleRepository,
    required this._generationScheduler,
    required this._timeProvider,
  });

  final ArticleRepository _articleRepository;
  final BackgroundWorkScheduler _generationScheduler;
  final TimeProvider _timeProvider;

  /// 每批固定生成的最大文章数。无论用户选择每天看 1~5 篇，系统总是生成 5 篇。
  static const int maxArticlesPerBatch = 5;

  static const Map<String, List<String>> contentCategories = {
    'LOW': ['DAILY_CONVERSATION', 'SCENE_DESCRIPTION', 'SIMPLE_STORY'],
    'MEDIUM': ['NEWS', 'EXPOSITORY', 'ARGUMENTATIVE', 'PERSONAL_ESSAY'],
    'HIGH': [
      'ACADEMIC_EXCERPT',
      'DEBATE_SPEECH',
      'LEGAL_DOCUMENT',
      'ART_CRITICISM',
      'CLASSIC_NOVEL_EXCERPT',
    ],
  };

  /// 确保有未来可用的 READY 批次。
  ///
  /// 逻辑：
  /// 1. 查找 daily_learning 的 max(ref_batch_date)
  /// 2. 查找 user_settings 的难度
  /// 3. 检查是否有 generated_on > max(ref_batch_date) 且 difficulty=当前难度的 READY 批次
  ///    - 有 → 跳过（已有未来可用批次）
  ///    - 无 → 创建新批次并调度 Worker 生成
  Future<void> call(String difficulty, int dailyCount) async {
    final today = _timeProvider.todayDateString();
    final maxRefDate = await _articleRepository.getMaxRefBatchDate() ?? today;
    // 2026-08-12：预生成批次打"明天"日期——今天消费的批次（generated_on=今天）
    // 仍占用 UNIQUE(difficulty, generated_on)，预生成必须落在不同日期；
    // 且"明天"日期天然满足消费规则（>= 最后消费日），断签多天依然可消费。
    final nextDate = _timeProvider.nextDateString();
    debugPrint('[TriggerNextBatch] call: difficulty=$difficulty dailyCount=$dailyCount today=$today nextDate=$nextDate maxRefDate=$maxRefDate');

    // 1. 检查是否有 generated_on >= max(ref_batch_date) 且 difficulty=当前难度的 READY 批次
    //    （2026-08-12 修复：>= 使批次等得起，断签一天不作废）
    //    忽略旧 seed 数据（generated_on 远早于 maxRefDate，不满足 >= 条件）
    final unassigned =
        await _articleRepository.getUnassignedReadyBatches(difficulty, maxRefDate);
    debugPrint('[TriggerNextBatch] unassigned READY batches: ${unassigned.length}');
    if (unassigned.isNotEmpty) return; // 已有比已分配批次更新的可用批次

    // 2. 检查预生成目标日期（明天）是否已有**未消费**的同难度批次。
    //    避免在一天内产生多个同难度批次（Worker 进行中的防重入）。
    //    2026-08-12 修复：已消费的批次不算"进行中"——当天创建当天消费
    //    后必须允许再创建（预生成下一次），否则断签后链条无法自愈。
    final existing = await _articleRepository
        .getUnassignedBatchByDifficultyAndDate(difficulty, nextDate);
    debugPrint('[TriggerNextBatch] unassigned batch for $difficulty/$nextDate: ${existing?.id}');
    if (existing != null) return; // 明天已有未消费的同难度批次，Worker 继续

    // 3. 没有可用的，创建新批次并调度 Worker
    final batchId = await _articleRepository.createBatch(
      difficulty,
      generatedOn: nextDate,
    );
    debugPrint('[TriggerNextBatch] created batch $batchId');
    await _articleRepository.createArticles(batchId, pickCategories(difficulty));
    debugPrint('[TriggerNextBatch] scheduling Worker for batch $batchId');
    await _generationScheduler.scheduleBatchGeneration(batchId);
    debugPrint('[TriggerNextBatch] Worker scheduled for batch $batchId');
  }

  /// Round-robin category selection from the difficulty group.
  List<String> pickCategories(String difficulty) {
    final available = contentCategories[difficulty] ?? contentCategories['MEDIUM']!;
    final offset = (_timeProvider.nowMillis() % 1000) % available.length;
    return [
      for (var i = 0; i < maxArticlesPerBatch; i++)
        available[(offset + i) % available.length],
    ];
  }
}
