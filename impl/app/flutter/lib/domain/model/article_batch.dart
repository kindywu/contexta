import 'article.dart';

/// 文章批次领域模型（对齐 Kotlin ArticleBatch.kt；2026-08-13 计划 B Task 6
/// 移除本地生成管道后删去 blockedReason/blockedAt）。
class ArticleBatch {
  final int id;
  final BatchStatus status;
  final String difficultyLevelSnapshot;
  final String? generatedOn;
  final String lastUpdatedAt;
  final List<Article> articles;

  const ArticleBatch({
    required this.id,
    required this.status,
    required this.difficultyLevelSnapshot,
    required this.generatedOn,
    required this.lastUpdatedAt,
    this.articles = const [],
  });

  @override
  String toString() => 'ArticleBatch(id=$id, status=$status, '
      'difficultyLevelSnapshot=$difficultyLevelSnapshot, '
      'generatedOn=$generatedOn, lastUpdatedAt=$lastUpdatedAt, articles=$articles)';
}

/// 批次生成状态（存储层用大写枚举名 TEXT）。
enum BatchStatus {
  pending('PENDING'),
  generating('GENERATING'),
  ready('READY'),
  current('CURRENT'),
  blocked('BLOCKED');

  const BatchStatus(this.dbValue);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  String toDbValue() => dbValue;

  static BatchStatus fromDbValue(String value) {
    for (final s in values) {
      if (s.dbValue == value) return s;
    }
    throw ArgumentError('Unknown BatchStatus: $value');
  }

  @override
  String toString() => dbValue;
}
