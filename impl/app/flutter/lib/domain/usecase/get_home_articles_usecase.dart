import '../generation/article_prompts.dart';
import '../model/article.dart';

/// 从 HomeViewModel 提取的文章过滤和排序逻辑（对照 Kotlin GetHomeArticlesUseCase.kt）。
///
/// ⚠️ [displayLimit] 来自 `daily_learning.dailyCountSnapshot`（学习分配时抓拍的用户设置），
/// 不是当前 `user_settings.daily_article_count`。修改篇数设置后，已有阅读记录不受影响。
///
/// 领域规则：按用户难度匹配文章，不足时返回全部已生成文章。
class GetHomeArticlesUseCase {
  /// 过滤并排序当前批次的文章。
  ///
  /// [articles] 批次所有文章（通常 5 篇，见 TriggerNextBatchUseCase.maxArticlesPerBatch）
  /// [userDifficulty] 用户当前难度等级（取自 `user_settings`）
  /// [displayLimit] 每批展示数量（取自 `daily_learning.dailyCountSnapshot`，可能 ≠ 当前设置）
  List<Article> call(
    List<Article> articles,
    String userDifficulty,
    int displayLimit,
  ) {
    final matching = articles
        .where((a) => a.status != ArticleStatus.pending)
        .where((a) => categoryToDifficulty(a.contentCategory) == userDifficulty)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final candidates = matching.isNotEmpty
        ? matching
        : articles.where((a) => a.status != ArticleStatus.pending).toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return candidates.take(displayLimit).toList();
  }
}
