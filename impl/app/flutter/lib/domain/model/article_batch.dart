import 'article.dart';

/// 文章批次领域模型（对齐 Kotlin ArticleBatch.kt）。
class ArticleBatch {
  final int id;
  final BatchStatus status;
  final String difficultyLevelSnapshot;
  final String? generatedOn;
  final String lastUpdatedAt;
  final String? blockedReason;
  final String? blockedAt;
  final List<Article> articles;

  const ArticleBatch({
    required this.id,
    required this.status,
    required this.difficultyLevelSnapshot,
    required this.generatedOn,
    required this.lastUpdatedAt,
    this.blockedReason,
    this.blockedAt,
    this.articles = const [],
  });

  @override
  String toString() => 'ArticleBatch(id=$id, status=$status, '
      'difficultyLevelSnapshot=$difficultyLevelSnapshot, '
      'generatedOn=$generatedOn, lastUpdatedAt=$lastUpdatedAt, '
      'blockedReason=$blockedReason, blockedAt=$blockedAt, articles=$articles)';
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
