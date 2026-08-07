import '../repository/article_repository.dart';
import '../time/time_provider.dart';

/// 查找并激活匹配的种子批次（首次安装时由 seedDatabase 写入的 READY 批次）
/// （对照 Kotlin ActivateSeedBatchUseCase.kt）。
///
/// 在 onboarding 完成后调用，将种子批次分配给今天的 daily_learning，
/// 让用户立即可看到初始文章，同时触发后续批次的后台生成。
///
/// **在新系统下，[StartupOrchestrationUseCase] 已经能自动完成此任务。**
/// 此 Use Case 作为 onboarding 完成后的立即激活，确保用户在跳转到首页前
/// 批次已被分配，避免首页闪烁。
class ActivateSeedBatchUseCase {
  ActivateSeedBatchUseCase({
    required this._articleRepository,
    required this._timeProvider,
  });

  final ArticleRepository _articleRepository;
  final TimeProvider _timeProvider;

  /// 激活种子批次：查找匹配的 READY 批次并分配给今天。
  ///
  /// 返回 true 找到并激活了种子批次，false 无匹配种子。
  Future<bool> call(String difficulty, int dailyCount) async {
    final batch = await _articleRepository.findNextReadyBatch(difficulty, null);
    if (batch == null) return false;

    // 即使 assign 失败（今天已有记录），也算找到种子了
    await _articleRepository.assignBatchForToday(
      batch.id,
      batch.generatedOn ?? _timeProvider.todayDateString(),
      dailyCount,
    );
    return true;
  }
}
