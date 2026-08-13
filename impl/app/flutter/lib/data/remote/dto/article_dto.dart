/// 服务端每日文章 DTO（GET /api/articles/today 契约，字段名精确 snake_case）：
///
/// ```json
/// {id, target_date, difficulty, content_category, order_index, title,
///  status, regenerate_count, paragraphs: [{order_index, english_text,
///  chinese_translation}]}
/// ```
///
/// [regenerateCount] 为服务端重生成次数（本任务不落库——同步文章的
/// retryCount 恒 0，重试语义保留在服务端，见 sync_articles_usecase 注释）。
class ArticleDto {
  const ArticleDto({
    required this.id,
    required this.targetDate,
    required this.difficulty,
    required this.contentCategory,
    required this.orderIndex,
    required this.title,
    required this.status,
    required this.regenerateCount,
    required this.paragraphs,
  });

  /// 服务端文章 id（本地 article.server_article_id 幂等键）。
  final int id;

  /// 审核通过日期（yyyy-MM-dd）；批次 generatedOn 取此值，非本地 today。
  final String targetDate;

  /// 'LOW' | 'MEDIUM' | 'HIGH'（批次 difficulty_level_snapshot）。
  final String difficulty;

  final String contentCategory;

  /// 批次内顺序（1 起）。
  final int orderIndex;

  final String title;

  /// 服务端状态（同步落库恒 'SUCCESS'）。
  final String status;

  final int regenerateCount;

  final List<ArticleParagraphDto> paragraphs;

  factory ArticleDto.fromJson(Map<String, dynamic> json) => ArticleDto(
    id: json['id'] as int,
    targetDate: json['target_date'] as String,
    difficulty: json['difficulty'] as String,
    contentCategory: json['content_category'] as String,
    orderIndex: json['order_index'] as int,
    title: json['title'] as String,
    status: json['status'] as String,
    regenerateCount: json['regenerate_count'] as int,
    paragraphs: [
      for (final p in (json['paragraphs'] as List? ?? const []))
        ArticleParagraphDto.fromJson((p as Map).cast<String, dynamic>()),
    ],
  );
}

/// 段落 DTO（服务端契约 {order_index, english_text, chinese_translation}）。
class ArticleParagraphDto {
  const ArticleParagraphDto({
    required this.orderIndex,
    required this.englishText,
    required this.chineseTranslation,
  });

  final int orderIndex;
  final String englishText;
  final String chineseTranslation;

  factory ArticleParagraphDto.fromJson(Map<String, dynamic> json) =>
      ArticleParagraphDto(
        orderIndex: json['order_index'] as int,
        englishText: json['english_text'] as String,
        chineseTranslation: json['chinese_translation'] as String,
      );
}
