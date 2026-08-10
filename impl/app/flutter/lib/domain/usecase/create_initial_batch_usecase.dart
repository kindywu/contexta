import '../repository/article_repository.dart';
import '../time/time_provider.dart';
import 'trigger_next_batch_usecase.dart';

/// 为首次使用创建初始批次（onboarding 完成后或首次打开 app 时）
/// （对照 Kotlin CreateInitialBatchUseCase.kt）。
///
/// 创建批次 → 创建文章 → 分配到今天的 daily_learning → 调用方触发生成 Worker。
class CreateInitialBatchUseCase {
  CreateInitialBatchUseCase({
    required this._articleRepository,
    required this._triggerNextBatch,
    required this._timeProvider,
  });

  final ArticleRepository _articleRepository;
  final TriggerNextBatchUseCase _triggerNextBatch;
  final TimeProvider _timeProvider;

  /// 创建初始批次并编排文章生成。返回创建的 batch ID（调用方可用它触发 WorkManager）。
  Future<int> call(String difficulty, int dailyCount) async {
    final batchId = await _articleRepository.createBatch(difficulty);
    final categories = _triggerNextBatch.pickCategories(difficulty);
    await _articleRepository.createArticles(batchId, categories);

    // 立即将当前批次分配到今天的 daily_learning，
    // 这样用户打开首页时能看到等待状态
    await _articleRepository.assignBatchForToday(
      batchId,
      _timeProvider.todayDateString(),
      dailyCount,
    );

    return batchId;
  }
}
