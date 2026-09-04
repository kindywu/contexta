/// 服务端文章 DTO（GET /api/articles/delivery 投放响应的 articles 项契
/// 约，字段名精确 snake_case）：
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

  /// 审核通过日期（yyyy-MM-dd）；批次 generatedOn 取投放响应 delivery_date
  /// （投放日），非本文值——投放集可跨天，同集各篇 targetDate 可能不同。
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

/// 服务端投放响应 DTO（GET /api/articles/delivery 契约）：
/// `{delivery_date, articles: [ArticleDto...]}`。
/// delivery_date = 服务器时区今天（本地批次 generated_on 取此值）。
class ArticleDeliveryDto {
  const ArticleDeliveryDto({required this.deliveryDate, required this.articles});

  /// 服务器时区交付日（yyyy-MM-dd）。
  final String deliveryDate;

  final List<ArticleDto> articles;

  factory ArticleDeliveryDto.fromJson(Map<String, dynamic> json) =>
      ArticleDeliveryDto(
        deliveryDate: json['delivery_date'] as String,
        articles: [
          for (final e in (json['articles'] as List? ?? const []))
            ArticleDto.fromJson((e as Map).cast<String, dynamic>()),
        ],
      );
}
