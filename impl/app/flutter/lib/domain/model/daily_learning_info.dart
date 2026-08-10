import 'article_batch.dart';

/// 每日学习记录（含关联的批次信息，对齐 Kotlin DailyLearningInfo.kt）。
/// 用于首页展示用户的学习历史。
class DailyLearningInfo {
  final String learningDate;
  final int dailyCountSnapshot;
  final ArticleBatch batch;

  const DailyLearningInfo({
    required this.learningDate,
    required this.dailyCountSnapshot,
    required this.batch,
  });

  @override
  String toString() => 'DailyLearningInfo(learningDate=$learningDate, '
      'dailyCountSnapshot=$dailyCountSnapshot, batch=$batch)';
}
